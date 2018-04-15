
module Invariants

using JuLIP, NeighbourLists, StaticArrays, ForwardDiff

import Base: length
import JuLIP: cutoff, energy, forces
import JuLIP.Potentials: evaluate, evaluate_d

const CRg = CartesianRange
const CInd = CartesianIndex
const Tup{M} = NTuple{M, Int}
const VecTup{M} = Vector{NTuple{M, Int}}

export NBody, NBodyIP, PolyInvariants, InvInvariants, Dictionary,
      gen_tuples, gen_basis

# ==================================================================
#           INVARIANTS
# ==================================================================


"""
`invariants(r::SVector{M,T})` : computes the invariant descriptors as a function of the
lengths in a simplex. The order is lexicographical, i.e.,

* 2-body: `r::SVector{1}`
* 3-body: `r::SVector{3}`, order is irrelevant, but `r = [r12, r13, r23]`
* 4-body: `r::SVector{6}`, order is `r = [r12, r13, r14, r23, r24, r34]`
* 5-body: `r::SVector{10}`, analogous
"""
function invariants end


"""
Use polynomials in r as the invariants
"""
struct PolyInvariants
end

invariants(::PolyInvariants, r::SVector{3, T}) where {T} = SVector{3, T}(
   r[1]+r[2]+r[3],
   r[1]*r[2] + r[1]*r[3] + r[2]*r[3],
   r[1]*r[2]*r[3] )

grad_invariants(::PolyInvariants, r::SVector{3, T}) where {T} = SVector{3, SVector{3,T}}(
      SVector{3,T}(1,1,1),
      SVector{3,T}(r[2]+r[3], r[1]+r[3], r[1]+r[2]),
      SVector{3,T}(r[2]*r[3], r[1]*r[3], r[1]*r[2])    )


"""
Use polynomials in r^{-1} as the invariants
"""
struct InvInvariants
end

invariants(::InvInvariants, r::SVector{M, T}) where {M, T} = invariants_inv(1 ./ r)
grad_invariants(::InvInvariants, r::SVector{M, T}) where {M, T} = grad_invariants_inv(1 ./ r)

invariants_inv(s::SVector{3, T}) where {T} = SVector{3, T}(
   s[1]+s[2]+s[3],
   s[1]*s[2] + s[1]*s[3] + s[2]*s[3],
   s[1]*s[2]*s[3] )

function grad_invariants_inv(s::SVector{3, T}) where {T}
   t = - s.^2
   return SVector{3, SVector{3,T}}(
      SVector{3,T}(t[1],t[2],t[3]),
      SVector{3,T}(t[1]*(s[2]+s[3]), t[2]*(s[1]+s[3]), t[3]*(s[1]+s[2])),
      SVector{3,T}(t[1]*s[2]*s[3], t[2]*s[1]*s[3], t[3]*s[1]*s[2])    )
end

"""
`inv_degrees(::Val{N})` where `N` is the body-order returns a
tuple of polynomials degrees corresponding to the degrees of the
individual invariants.  E.g. for 3-body, the invariants are
r1 + r2 + r3, r1 r2 + r1 r3 + r2 r3, r1 r2 r3, and the corresponding
degrees are `(1, 2, 3)`.
"""
inv_degrees(::Val{3}) = (1, 2, 3)

# TODO
# struct ExpInvariants
# end

# -------------- 4-body invariants ----------------

# TODO: reorder to obtain increasing degree?
inv_degrees(::Val{4}) = (1, 2, 3, 4, 2, 3, 3, 4, 5, 6, 9)

const _2 = 2.0^(-0.5)
const _3 = 3.0^(-0.5)
const _6 = 6.0^(-0.5)
const _12 = 12.0^(-0.5)
#                     ρ1=r1  ρ2=r2  ρ3=r3  ρ4=    ρ5=r5  ρ6=
#
const r2ρ = @SMatrix [   1 0 0 0 0 0
                         0 1 0 0 0 0
                         0 0 1 0 0 0
                         0 0 0 0 0 1
                         0 0 0 0 1 0
                         0 0 0 1 0 0 ]  # to account for the different ordering

const R2Q = @SMatrix [ _6     _6     _6    _6     _6     _6
                        _2      0      0   -_2      0      0
                         0     _2      0     0    -_2      0
                         0      0     _2     0      0    -_2
                         0    0.5   -0.5     0    0.5   -0.5
                        _3   -_12   -_12    _3   -_12   -_12 ]

const R2Qxr2ρ = R2Q * r2ρ

function invariants_inv(s::SVector{6, T}) where {T}
   Q = R2Qxr2ρ * s
   Q2 = Q .* Q
   Q2_34, Q2_24, Q2_23 = Q2[3] * Q2[4], Q2[2] * Q2[4], Q2[2] * Q2[3]
   rt3 = sqrt(3.0)
   Q_56 = Q[5] * Q[6]

   return SVector{11, T}(
      # I1
      (Q[1]),
      # I2
      (Q2[2] + Q2[3] + Q2[4]),
      # I3
      (Q[2] * Q[3] * Q[4]),
      # I4
      (Q2_34 + Q2_24 + Q2_23),
      # I5
      (Q2[5] + Q2[6]),
      # I6
      (Q[6] * (Q2[6] - 3*Q2[5])),
   # ),
   # SVector{5, T}(
      # I7
      (Q[6] * (2*Q2[2] - Q2[3] - Q2[4]) + rt3 * Q[5] * (Q2[3] - Q2[4])),
      # I8
      (( (Q2[6] - Q2[5]) * (2*Q2[2] - Q2[3] - Q2[4])
            - 2 * rt3 * Q_56 * (Q2[3] - Q2[4]) )),
      # I9
      (( Q[6] * (2*Q2_34 - Q2_24 - Q2_23) + rt3 * Q[5] * (Q2_24 - Q2_23) )),
      # I10
      (( (Q2[6] - Q2[5])*(2*Q2_34 - Q2_24 - Q2_23)
                   - 2 * rt3 * Q_56 * (Q2_24 - Q2_23) )),
      # I11
      (( (Q2[3] - Q2[4]) * (Q2[4] - Q2[2]) * (Q2[2] - Q2[3]) *
            Q[5] * (3*Q2[6] - Q2[5]) ))
   )
end


function grad_invariants_inv(s::SVector{6, T}) where {T}
   t = - s.^(-2)
   J = ForwardDiff.jacobian(invariants_inv, s)
   return SVector{11, SVector{6, T}}(
      t .* J[1,:],
      t .* J[2,:],
      t .* J[3,:],
      t .* J[4,:],
      t .* J[5,:],
      t .* J[6,:],
      t .* J[7,:],
      t .* J[8,:],
      t .* J[9,:],
      t .* J[10,:],
      t .* J[11,:]
   )
end


# ==================================================================
#           Dictionary
#
# Here we can implement a lot of generalisations, e.g.,
#  - we can change the invariants (ok, already implemented)
#  - we can implement different cutoff functions  (or put them into the invariants)
#  - allow basis functions other than polynomials of the invariants
#
# ==================================================================


@pot struct Dictionary{TINV, T}
   I::TINV                    # which invariants
   # fcut::TC                   # cut-off function
   # dfcut::TDC                 # cut-off function derivative
   # d::Vector{TF}              # dictionary functions
   # dd::Vector{TDF}            # dictionary of derivatives
   rcut::T                    # cutoff radius
end


"""
`struct Dictionary` : specifies all details about the basis functions
"""
Dictionary

@inline invariants(D::Dictionary, r) = invariants(D.I, r)
@inline grad_invariants(D::Dictionary, r) =  grad_invariants(D.I, r)

@inline fcut(D::Dictionary, r::Number) = (r - D.rcut)^2 * (r < D.rcut)
@inline fcut_d(D::Dictionary, r::Number) = 2 * (r - D.rcut) * (r < D.rcut)

@inline evaluate(D::Dictionary, i, Q) = @fastmath Q^i
@inline evaluate_d(D::Dictionary, i, Q) = (i == 0 ? 0.0 : (@fastmath i * Q^(i-1)))

cutoff(D::Dictionary) = D.rcut

fcut(D::Dictionary, r::AbstractVector) = prod(fcut(D, rr) for rr in r)

function fcut_d(D::Dictionary, r::SVector{M,T}) where {M, T}
   if maximum(r) > D.rcut-eps()
      return zero(SVector{M,T})
   end
   # now we know that they are all inside
   f = fcut(D, r)
   return (2 * f) ./ (r - D.rcut)
end

Dictionary(T::Type, rcut) = Dictionary(T(), rcut)


# ==================================================================
#           Polynomials of Invariants
# ==================================================================


@pot struct NBody{N, M, T, TINV} <: AbstractCalculator
   t::VecTup{M}               # tuples
   c::Vector{T}               # coefficients
   D::Dictionary{TINV, T}
   valN::Val{N}
end

"""
`struct NBody{N, M, T <: AbstractFloat, TI <: Integer, TF}`

A struct storing the information for a pure N-body potential, i.e., containing
*only* terms of a specific body-order. Several `NBody`s can be
combined into an interatomic potential via `NBodyIP`.

### Fields

* `t::Vector{NTuple{M,TI}}` : list of M-tuples containing basis function information
e.g., if M = 3, α = t[1] is a 3-vector then this corresponds to the basis function
`f[α[1]](Q[1]) * f[α[2]](Q[2]) * f[α[3]](Q[3])` where `Q` are the 3-body invariants.

* `c`: vector of coefficients for the basis functions

* `d`: 1D function dictionary

* `rcut` : cut-off radius (all functions `f in d` must have this cutoff radius)
"""
NBody


edges2bo(M) = ceil(Int, sqrt(2*M))

NBody(t::VecTup{M}, c, D) where {M} =
      NBody(t, c, D, Val(edges2bo(M)))

NBody(t::Tup, c, D) = NBody([t], [c], D)

NBody(B::Vector{TB}, c, D) where {TB <: NBody} =
   NBody([b.t[1] for b in B], c, D)

length(V::NBody) = length(V.t)
cutoff(V::NBody) = cutoff(V.D)
bodyorder(V::NBody{N}) where {N} = N
dim(V::NBody{N,M}) where {N, M} = M

function energy(V::NBody{N, M, T}, at::Atoms{T}) where {N, M, T}
   nlist = neighbourlist(at, cutoff(V))
   Es = maptosites!(r -> V(r), zeros(length(at)), nbodies(N, nlist))
   return sum_kbn(Es)
end

function forces(V::NBody{N, M, T}, at::Atoms{T}) where {N, M, T}
   nlist = neighbourlist(at, cutoff(V))
   return scale!(maptosites_d!(r -> (@D V(r)),
                 zeros(SVector{3, T}, length(at)),
                 nbodies(N, nlist)), -1)
end

function forces(V::NBody{4, M, T}, at::Atoms{T}) where {M, T}
   nlist = neighbourlist(at, cutoff(V))
   evalfun = r -> evaluate(V, r)
   cfg = ForwardDiff.GradientConfig(evalfun, (@SVector ones(6)),
            ForwardDiff.Chunk{6}())
   return scale!(maptosites_d!(
                 r -> ForwardDiff.gradient(evalfun, r, cfg, Val(false)),
                 zeros(SVector{3, T}, length(at)),
                 nbodies(4, nlist)), -1)
end

# ---------------  3-body terms ------------------

function evaluate(V::NBody{3, M, T}, r::AbstractVector{TT})  where {M, T, TT}
   # @assert length(r) == M == 3
   E = 0.0
   D = V.D
   Q = invariants(D, r)         # SVector{NI, T}
   for (α, c) in zip(V.t, V.c)
      E += c * D(α[1], Q[1]) * D(α[2], Q[2]) * D(α[3], Q[3])
   end
   fc = fcut(D, r[1]) * fcut(D, r[2]) * fcut(D, r[3])
   return E * fc
end


function evaluate_d(V::NBody{3, M, T}, r::AbstractVector{T}) where {M, T}
   E = zero(T)
   dE = zero(SVector{M, T})
   D = V.D
   Q = invariants(D, r)           # SVector{NI, T}
   dQ = grad_invariants(D, r)     # SVector{NI, SVector{M, T}}
   for (α, c) in zip(V.t, V.c)
      f1 = D(α[1], Q[1])
      f2 = D(α[2], Q[2])
      f3 = D(α[3], Q[3])
      E += c * f1 * f2 * f3
      dE += c * ((@D D(α[1], Q[1])) * f2 * f3 * dQ[1] +
                 (@D D(α[2], Q[2])) * f1 * f3 * dQ[2] +
                 (@D D(α[3], Q[3])) * f2 * f1 * dQ[3] )
   end
   fc1, fc2, fc3 = fcut(D, r[1]), fcut(D, r[2]), fcut(D, r[3])
   dfc1, dfc2, dfc3 = fcut_d(D, r[1]), fcut_d(D, r[2]), fcut_d(D, r[3])
   fc = fc1 * fc2 * fc3
   fc_d = SVector{3, Float64}(
      dfc1 * fc2 * fc3, fc1 * dfc2 * fc3, fc1 * fc2 * dfc3)
   return dE * fc + E * fc_d
end


# ---------------  4-body terms ------------------

# a tuple α = (α1, …, α6, α7) means the following:
# with f[0] = 1, f[1] = I7, …, f[5] = I11 we construct the basis set
#   f[α7] * g(I1, …, I6)
# this means, that gen_tuples must generate 7-tuples instead of 6-tuples
# with the first 6 entries restricted by degree and the 7th tuple must
# be in the range 0, …, 5

function evaluate(V::NBody{4, M, T}, r::AbstractVector{TT})  where {M, T, TT}
   E = 0.0
   D = V.D
   II = invariants(D, r)         # SVector{NI, T}
   I = SVector{6}(II[1],II[2],II[3],II[4],II[5],II[6])
   J = SVector{6}(1.0, II[7], II[8], II[9], II[10], II[11])
   for (α, c) in zip(V.t, V.c)
      E += c * J[α[7]+1] * (
         D(α[1], I[1]) * D(α[2], I[2]) * D(α[3], I[3]) *
         D(α[4], I[4]) * D(α[5], I[5]) * D(α[6], I[6]) )
   end
   fc = fcut(D, r[1]) * fcut(D, r[2]) * fcut(D, r[3]) *
         fcut(D, r[4]) * fcut(D, r[5]) * fcut(D, r[6])
   return E * fc
end

evaluate_d(V::NBody{4, M, T}, r::AbstractVector{TT})  where {M, T, TT} =
   ForwardDiff.gradient(r_ -> evaluate(V, r_), r)

# function evaluate_d(V::NBody{4, M, T}, r::AbstractVector{T})  where {M, T}
#    E = 0.0
#    dE = zero(SVector{6, T})
#    D = V.D
#    I = invariants(D, r)         # SVector{NI, T}
#    DI = ForwardDiff.jacobian(r_->invariants(D, r_), r)
#    DII = DI[SVector{6,Int}(1,2,3,4,5,6), :]
#    J = SVector{6}(1.0, I[7], I[8], I[9], I[10], I[11])
#    temp = zero(MVector{6, T})
#    for (α, c) in zip(V.t, V.c)
#       f1 = D(α[1], I[1])
#       f2 = D(α[2], I[2])
#       f3 = D(α[3], I[3])
#       f4 = D(α[4], I[4])
#       f5 = D(α[5], I[5])
#       f6 = D(α[6], I[6])
#       f = f1 * f2 * f3 * f4 * f5 * f6
#       E += c * J[α[7]+1] * f
#       if α[7] == 0
#          DJ = zero(SVector{6,T})
#       else
#          DJ = DI[6+α[7], :]
#       end
#       cJ = c * J[1+α[7]]
#       temp[1] = (@D D(α[1], I[1])) * f2*f3*f4*f5*f6
#       temp[2] = (@D D(α[2], I[2])) * f1*f3*f4*f5*f6
#       temp[3] = (@D D(α[3], I[3])) * f1*f2*f4*f5*f6
#       temp[4] = (@D D(α[4], I[4])) * f1*f2*f3*f5*f6
#       temp[5] = (@D D(α[5], I[5])) * f1*f2*f3*f4*f6
#       temp[6] = (@D D(α[6], I[6])) * f1*f2*f3*f4*f5
#       dE += c * (DJ * f + J[1+α[7]] * (DII * temp))
#
#       # dE += c * (DJ * f +
#       #    J[1+α[7]] * (DII * SVector{6, T}(
#       #       (@D D(α[1], I[1])) * f2*f3*f4*f5*f6,
#       #       (@D D(α[2], I[2])) * f1*f3*f4*f5*f6,
#       #       (@D D(α[3], I[3])) * f1*f2*f4*f5*f6,
#       #       (@D D(α[4], I[4])) * f1*f2*f3*f5*f6,
#       #       (@D D(α[5], I[5])) * f1*f2*f3*f4*f6,
#       #       (@D D(α[6], I[6])) * f1*f2*f3*f4*f5 ) ))
#             # + cJ * (@D D(α[1], I[1])) * f2*f3*f4*f5*f6 * DI[1,:]
#       #       + cJ * (@D D(α[2], I[2])) * f1*f3*f4*f5*f6 * DI[2,:]
#       #       + cJ * (@D D(α[3], I[3])) * f1*f2*f4*f5*f6 * DI[3,:]
#       #       + cJ * (@D D(α[4], I[4])) * f1*f2*f3*f5*f6 * DI[4,:]
#       #       + cJ * (@D D(α[5], I[5])) * f1*f2*f3*f4*f6 * DI[5,:]
#       #       + cJ * (@D D(α[6], I[6])) * f1*f2*f3*f4*f5 * DI[6,:]
#       # )
#    end
#    fc1, dfc1 = fcut(D, r[1]), fcut_d(D, r[1])
#    fc2, dfc2 = fcut(D, r[2]), fcut_d(D, r[2])
#    fc3, dfc3 = fcut(D, r[3]), fcut_d(D, r[3])
#    fc4, dfc4 = fcut(D, r[4]), fcut_d(D, r[4])
#    fc5, dfc5 = fcut(D, r[5]), fcut_d(D, r[5])
#    fc6, dfc6 = fcut(D, r[6]), fcut_d(D, r[6])
#    fc = fc1 * fc2 * fc3 * fc4 * fc5 * fc6
#    dfc = SVector{6, T}(
#          dfc1 *  fc2 *  fc3 *  fc4 *  fc5 *  fc6,
#           fc1 * dfc2 *  fc3 *  fc4 *  fc5 *  fc6,
#           fc1 *  fc2 * dfc3 *  fc4 *  fc5 *  fc6,
#           fc1 *  fc2 *  fc3 * dfc4 *  fc5 *  fc6,
#           fc1 *  fc2 *  fc3 *  fc4 * dfc5 *  fc6,
#           fc1 *  fc2 *  fc3 *  fc4 *  fc5 * dfc6 )
#    return dE * fc + E * dfc
# end

# ==================================================================
#           The Final Interatomic Potential
# ==================================================================


"""
`NBodyIP` : wraps `NBody`s into a JuLIP calculator, defining
`energy`, `forces` and `cutoff`.
"""
struct NBodyIP <: AbstractCalculator
   orders::Vector{NBody}
end

cutoff(V::NBodyIP) = maximum( cutoff.(V.orders) )
energy(V::NBodyIP, at::Atoms) = sum( energy(Vn, at)  for Vn in V.orders )
forces(V::NBodyIP, at::Atoms) = sum( forces(Vn, at)  for Vn in V.orders )

function NBodyIP(basis, coeffs)
   orders = NBody[]
   bos = bodyorder.(basis)
   for N = 2:maximum(bos)
      Ibo = find(bos .== N)  # find all basis functions that have the right bodyorder
      if length(Ibo) > 0
         D = basis[Ibo[1]].D
         V_N = NBody(basis[Ibo], coeffs[Ibo], D)
         push!(orders, V_N)  # collect them
      end
   end
   return NBodyIP(orders)
end




# ==================================================================
#           Generate a Basis
# ==================================================================

# TODO: rename this to nedges
tuple_length(::Val{2}) = 1
tuple_length(::Val{3}) = 3
tuple_length(::Val{4}) = 6

degree(α::Tup{3}) = α[1] + 2 * α[2] + 3 * α[3]

function degree(α::Tup{7})
   degs = inv_degrees(Val(4))
   d = sum(α[j] * degs[j] for j = 1:6)
   if α[7] > 0
      d += degs[6+α[7]]
   end
   return d
end


"""
`gen_tuples(N, deg; tuplebound = ...)` : generates a list of tuples, where
each tuple defines a basis function. Use `gen_basis` to convert the tuples
into a basis, or use `gen_basis` directly.

* `N` : body order
* `deg` : maximal degree
* `tuplebound` : a function that takes a tuple as an argument and returns
`true` if that tuple should be in the basis and `false` if not. The default is
`α -> (degree(α) <= deg)` i.e. the standard monomial degree. (note this is
the degree w.r.t. lengths, not w.r.t. invariants!)
"""
gen_tuples(N, deg; tuplebound = (α -> (degree(α) <= deg))) =
   gen_tuples(Val(N), Val(tuple_length(Val(N))), deg, tuplebound)


# ------------- 3-body tuples -------------

function gen_tuples(vN::Val{3}, vK::Val{K}, deg, tuplebound) where {K}
   t = Tup{K}[]
   for I in CRg(CInd(ntuple(0, vK)), CInd(ntuple(deg, vK)))
      if tuplebound(I.I)
         push!(t, I.I)
      end
   end
   return t
end

# ------------- 4-body tuples -------------

# little hack to make 4-body work: TODO: make this more general!!!!!
function gen_tuples(vN::Val{4}, vM::Val{M}, deg, tuplebound) where {M}
   t = Tup{7}[]
   Ilo = CInd{7}(0,0,0,0,0,0,0)
   degs = inv_degrees(vN)
   idegs = ceil.(Int, deg ./ degs)[1:7]
   Ihi = CInd{7}(idegs)
   for I in CRg(Ilo, Ihi)
      if tuplebound(I.I)
         push!(t, I.I)
      end
   end
   return t
end


"""
`gen_basis(N, D, deg; tuplebound = ...)` : generates a basis set of
`N`-body functions, with dictionary `D`, maximal degree `deg`; the precise
set of basis functions constructed depends on `tuplebound` (see `?gen_tuples`)
"""
gen_basis(N, D, deg; kwargs...) = gen_basis(gen_tuples(N, deg; kwargs...), D)

gen_basis(ts::VecTup, D::Dictionary) = [NBody(t, 1.0, D) for t in ts]

end