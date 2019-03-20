"""

`module Regularisers`

## Old Documentation Copy-Pasted ...

`regularise_2b(B, r0, r1; creg = 1e-2, Nquad = 20)`

construct a regularising stabilising matrix that acts only on 2-body
terms.

* `B` : basis
* `r0, r1` : upper and lower bound over which to integrate
* `creg` : multiplier
* `Nquad` : number of quadrature / sample points

```
   I = ∑_r h | ∑_j c_j ϕ_j''(r) |^2
     = ∑_{i,j} c_i c_j  ∑_r h ϕ_i''(r) ϕ_j''(r)
     = c' * M * c
   M_ij = ∑_r h ϕ_i''(r) ϕ_j''(r) = h * Φ'' * Φ''
   Φ''_ri = ϕ_i''(r)
```


`regularise(N, B, r0, r1; kwargs...)`

* `N::Integer` : body order
* `B::Vector` : basis
"""
module Regularisers

# TODO: move all this into NBodyIPs!

using StaticArrays
using JuLIP: AbstractCalculator
using JuLIP.Potentials: evaluate_d
using NBodyIPs: bodyorder, transform, evaluate_many_ricoords!, descriptor,
                  inv_transform, split_basis, BondLengthDesc, IdTransform
using NBodyIPs.Polys: NBPoly
using NBodyIPs.EnvIPs: EnvIP
using LinearAlgebra: I
using NBodyIPs.Sobol: filtered_sobol, filtered_cart_sobol, bl_is_simplex

import Base: Matrix, Dict

export BLRegulariser, BLReg, BARegulariser, BAReg,
       Regulariser

macro def(name, definition)
    return quote
        macro $(esc(name))()
            esc($(Expr(:quote, definition)))
        end
    end
end


abstract type NBodyRegulariser{N} end

@def nbregfields begin
   N::Int
   npoints::Int
   creg::T
   r0::T
   r1::T
   transform
   sequence::Symbol
   freg::Function
   valN::Val{N}
end

struct BLRegulariser{N, T} <: NBodyRegulariser{N}
   @nbregfields
end

struct BARegulariser{N, T} <: NBodyRegulariser{N}
   @nbregfields
end

struct EnergyRegulariser{N, T} <: NBodyRegulariser{N}
   @nbregfields
end

Dict(reg::NBodyRegulariser) = Dict(
   "type" => string(typeof(reg)),
   "N" => reg.N,
   "npoints" => reg.npoints,
   "creg" => reg.creg,
   "r0" => reg.r0,
   "r1" => reg.r1,
   "sequence" => string(reg.sequence),
   "transform" => Dict(reg.transform) )


const BLReg = BLRegulariser
const BAReg = BARegulariser
const EReg = BARegulariser

BLRegulariser(N, r0, r1;
             creg = 1.0,
             npoints = Nquad(Val(N)),
             sequence = :sobol,
             transform = IdTransform(),
             freg = laplace_regulariser) =
   BLRegulariser(N, npoints, creg, r0, r1, transform, sequence, freg, Val(N))

BARegulariser(N, r0, r1;
             npoints = Nquad(Val(N)),
             creg = 1.0,
             transform = IdTransform(),
             sequence = :sobol,
             freg = laplace_regulariser) =
   BARegulariser(N, npoints, creg, r0, r1, transform, sequence, freg, Val(N))

# TODO: revisit this one!
# EnergyRegulariser(N, r0, r1;
#             npoints = Nquad(Val(N)),
#             creg = 0.1,
#             sequence = :sobol) =
#    EnergyRegulariser(N, npoints, creg, r0, r1, sequence, energy_regulariser, Val(N))


_bainvt(inv_t, x::StaticVector{1}) =
      inv_t.(x), SVector()
_bainvt(inv_t, x::StaticVector{3}) =
      SVector(inv_t(x[1]), inv_t(x[2])), SVector(x[3])
_bainvt(inv_t, x::StaticVector{6}) =
      SVector(inv_t(x[1]), inv_t(x[2]), inv_t(x[3])),  SVector(x[4], x[5], x[6])

#
# this converts the Regulariser type information to a matrix that can be
# attached to the LSQ problem.
#
function Matrix(reg::NBodyRegulariser{N}, B::Vector{<: AbstractCalculator};
                verbose=false
                ) where {N}

   Ib = findall(bodyorder.(B) .== N)
   if isempty(Ib)
      verbose && warn("""Trying to construct a $N-body regulariser, but no basis
                         function with bodyorder $N exists.""")
      Ψreg = zeros(0, length(B))
      Yreg = zeros(0, 1)
      return Ψreg, Yreg
   end
   # scalar inverse transform
   inv_t = x -> inv_transform(reg.transform, x)

   # filter
   if reg isa BLRegulariser
      # vectorial inverse transform
      inv_tv = x -> inv_t.(x)
      filter = x -> bl_is_simplex( inv_tv(x) )
      x0 = transform(reg.transform, reg.r0) * SVector(ones((N*(N-1))÷2)...)
      x1 = transform(reg.transform, reg.r1) * SVector(ones((N*(N-1))÷2)...)
   elseif reg isa BARegulariser
      inv_tv = x -> _bainvt(inv_t, x)
      filter = x -> ba_is_simplex( inv_tv(x)... )
      x0 = vcat( transform(reg.transform, reg.r0) * SVector(ones(N-1)...),
                 - SVector(ones( ((N-1)*(N-2))÷2 )...) )
      x1 = vcat( transform(reg.transform, reg.r1) * SVector(ones(N-1)...),
                 SVector(ones( ((N-1)*(N-2))÷2 )...) )
   else
      error("Unknown type of reg: `typeof(reg) == $(typeof(reg))`")
   end

   if N == 2
      # uniform grid in 2d...
      X = SVector.(range(x0, x1, length = reg.npoints))
   else
      if reg.sequence == :sobol
         # construct a low discrepancy sequence
         X = filtered_sobol(x0, x1, filter; npoints=reg.npoints, nfailed=100*reg.npoints)
      elseif reg.sequence == :cart
         error("TODO: implement `sequence == :cart`")
      elseif reg.sequence isa Vector
         # this is intended to put the regulariser on configs in the database
         error("TODO: implement `sequence isa Vector`")
      else
         error("unknown argument `sequence = $sequence`")
      end
   end

   # loop through sobol points and collect the laplacians at each point.
   Ψreg = reg.creg/length(X) * assemble_reg_matrix(X, [b for b in B[Ib]], length(B),
                                                   Ib, inv_tv, reg.freg)
   Yreg = zeros(size(Ψreg, 1))
   return Ψreg, Yreg
end


_envdeg_(b::NBPoly) = 0
_envdeg_(b::EnvIP) = b.t

regeval_d(b::NBPoly, args...) = evaluate_d(b, args...)
regeval_d(b::EnvIP, args...) = evaluate_d(b.Vr, args...)

_Vr(b::NBPoly) = b
_Vr(b::EnvIP) = b.Vr

# function regularise_2b(B::Vector, r0::Number, r1::Number, creg, Nquad)
#    I2 = findall(bodyorder.(B) .== 2)
#    maxenvdeg = maximum(_envdeg_.(B[I2]))
#    rr = range(r0, stop=r1, length=Nquad)
#    Φ = [ zeros(Nquad, length(B))  for _=1:(maxenvdeg+1) ]
#    h = (r1 - r0) / (Nquad-1)
#    for (ib, b) in zip(I2, B[I2]), (iq, r) in enumerate(rr)
#       envdeg = _envdeg_(b)
#       Φ[envdeg+1][iq, ib] = (regeval_d(b, r+1e-2)-regeval_d(b, r-1e-2))/(2e-2) * sqrt(creg * h)
#    end
#    Φall = vcat(Φ...)
#    return Φall, zeros(size(Φall, 1))
# end


# # B = basis[Ib]
# # nB = length(basis)
# function assemble_reg_matrix(X, B, nB, Ib, inv_tv, freg)
#    @assert length(B) == length(Ib)
#    envdegs = unique(_envdeg_.(B))
#    Ψ = [ zeros(length(X), nB)  for _=1:length(envdegs) ]
#    Ib_deg = [ findall(_envdeg_.(B) .== p) for p in envdegs ]
#    for (ii, (Ψ_, Ib_, p)) in enumerate(zip(Ψ, Ib_deg, envdegs))
#       temp = zeros(length(Ib_))
#       B_ = [_Vr(b) for b in B[Ib_]]
#       for (ix, x) in enumerate(X)
#          Ψ_[ix, Ib[Ib_]] = freg(x, B_, temp, inv_tv)
#       end
#    end
#    return vcat(Ψ...)
# end

# B = basis[Ib]
# nB = length(basis)
function assemble_reg_matrix(X, B, nB, Ib, inv_tv, freg)
   @assert length(B) == length(Ib)
   # split the basis into "nice" parts
   Bord, Iord = split_basis(B; splitfun = b -> typeof(b))
   # allocate regularisation matrices for each of these
   Ψ = zeros(length(X), nB)
   # go through the basis subsets
   for n = 1:length(Bord)
      # indices of basis subset Bord[n] in basis
      Jb = Ib[Iord[n]]
      # temprary storage for the regularisation
      temp = zeros(length(Jb))
      # loop through points x ∈ X at which to apply the regularisation
      # function freg
      for (ix, x) in enumerate(X)
         Ψ[ix, Jb] = freg(x, Bord[n], temp, inv_tv)
      end
   end
   return Ψ
end




function laplace_regulariser(x::SVector{DIM,T}, B::Vector{<: AbstractCalculator},
                             temp::Vector{T}, inv_tv) where {DIM, T}
   if !isconcretetype(eltype(B))
      @warn("laplace_regulariser: `TB` is not a leaf type")
   end
   h = 1e-2
   r = inv_tv(x)
   evaluate_many_ricoords!(temp, B, r)
   L = 2 * DIM * copy(temp)

   EE = SMatrix{DIM,DIM}(1.0I)
   for j = 1:DIM
      rp = inv_tv(x + h * EE[:,j])
      evaluate_many_ricoords!(temp, B, rp)
      L -= temp
      rm = inv_tv(x - h * EE[:,j])
      evaluate_many_ricoords!(temp, B, rm)
      L -= temp
   end

   return L/h^2
end

# # TODO: revisit this regulariser!!!
# function energy_regulariser(x::SVector{DIM,T}, B::Vector{<: AbstractCalculator},
#                             temp::Vector{T}, inv_tv) where {DIM, T}
#    evaluate_many_ricoords!(temp, B, r)
#    return - temp
# end


# ==================================================================
#               DEFAULTS
# ==================================================================

Nquad(::Val{2}) = 100
Nquad(::Val{3}) = 1000
Nquad(::Val{4}) = 10_000

Regulariser(V::NBPoly{N, M, T, TD}, r0, r1; kwargs...
           ) where {N, M, T} where {TD <: BondLengthDesc} =
   BLReg(N, r0, r1; creg=1.0, npoints = Nquad(Val(N)),
                    transform = transform(V), kwargs... )


# ==================================================================

struct L2Regulariser
   a::Float64
end

function Matrix(reg::L2Regulariser, B::Vector{<: AbstractCalculator})
   return Matrix( a*I, (length(B), length(B)) ), zeros(length(B))
end


end