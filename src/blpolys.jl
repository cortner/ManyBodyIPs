
"""
`module BLPolys`

The exported symbols are
* `BLDictionary`: collects all the information about a basis
* `NBody`: an N-body function wrapped into a JuLIP calculator
* `poly_basis` : generate a basis of N-body functions

## Usage

## Notation

* `N` : N-body
* `M` : number of edges, i.e., M = N (N-1)/2
* `K` : length of the tuples defining polynomials, K = M+1
"""
module BLPolys

import StaticPolynomials

using JuLIP, NeighbourLists, StaticArrays

using NBodyIPs: NBodyFunction

using NBodyIPs.FastPolys: fpoly,
                          fpoly_d

import Base: length,
             Dict,
             ==

import JuLIP: cutoff

import JuLIP.Potentials: evaluate,
                         evaluate_d

import NBodyIPs: bodyorder,
                 fast,
                 evaluate_many!,
                 evaluate_many_d!,
                 degree,
                 combine_basis

const Tup{M} = NTuple{M, Int}
const VecTup{M} = Vector{NTuple{M, Int}}

export BLNBody,
       BLDictionary,
       bl_basis


"""
`struct BLDictionary` : specifies all details about the basis functions

## Convenience Constructor

`BLDictionary(ftrans, fcut[, rcut])`, where `ftrans`, `fcut` specify in one of several
ways how the dictionary is defined and `rcut` is the cutoff radius. If
the radius is not provided then `BLDictionary` will try to infer it from the
`fcut` argument. E.g.,
```julia
D = BLDictionary("r -> 1/r", (:cos, rcut1, rcut2))
```

Known symbols for the cutoff are
```
[:cos, :sw, :spline, :square, :cos2s]
```

## Developer Doc: Methods associated with a `D::BLDictionary`:

* `invariants`, `invariants_d`, `invariants_ed`: compute invariants and jacobian
   in transformed coordinates defined by `D.transform`
* `evaluate`, `evaluate_d`: evaluate the (univariate) basis
   function associated with this dictionary; at the moment only
   standard polynomials are admitted
* `fcut, fcut_d`: evulate the cut-off function and its derivative / gradient
   when interpreted as a product of cut-off functions
"""
struct BLDictionary{TT, TC}
   transform::TT
   cutoff::TC
end

function ==(D1::BLDictionary, D2::BLDictionary)
   return (D1.transform == D2.transform) && (D1.cutoff == D2.cutoff)
end


# generated functions for fast evaluation of monomials
include("fast_monomials.jl")

# import the raw symmetry invariant polynomials
include("invariants.jl")


# ==================================================================
#           DICTIONARY
# ==================================================================



# @generated function _sdot(a::T, B::SVector{N, T}) where {N, T}
#    quote
#       (@SVector [ a .* B[n]  for n = 1:$N ])
#    end
# end

@generated function _sdot(a::T, B::SVector{N, T}) where {N, T}
   code = "@SVector $T["
   for n = 1:N
      code *= "a .* B[$n],"
   end
   code = code[1:end-1] * "]"
   ex = parse(code)
   quote
      $ex
   end
end

@inline invariants(D::BLDictionary, r) = invariants(D.transform.(r))

@inline function invariants_d(D::BLDictionary, r)
   DI1, DI2 = invariants_d(D.transform.(r))
   t_d = D.transform_d.(r)
   return _sdot(t_d, DI1), _sdot(t_d, DI2)
end

@inline function invariants_ed(D::BLDictionary, r)
   t = D.transform.(r)
   I1, I2, DI1, DI2 = invariants_ed(t)
   t_d = D.transform_d.(r)
   return I1, I2, _sdot(t_d, DI1), _sdot(t_d, DI2)
end

@inline fcut(D::BLDictionary, r::Number) = D.fcut(r)

@inline fcut_d(D::BLDictionary, r::Number) = D.fcut_d(r)

@inline cutoff(D::BLDictionary) = D.rcut


# -------------------- generate dictionaries -------------------

BLDictionary(t, td, c, cd, rc) = BLDictionary(t, td, c, cd, rc, ("",""))

BLDictionary(D::BLDictionary, s::Tuple) =
      BLDictionary(D.transform, D.transform_d, D.fcut, D.fcut_d, D.rcut, s)

function BLDictionary(strans::String, scut::String)
   # @show strans, scut
   D = BLDictionary(eval(parse(ftrans_analyse(strans))),
                  eval(parse(scut)))
   return BLDictionary(D, (strans, scut))
end

BLDictionary(ftrans::AnalyticFunction, fcut::AnalyticFunction, rcut::AbstractFloat) =
      BLDictionary(ftrans.f, ftrans.f_d, fcut.f, fcut.f_d, rcut)

BLDictionary(ftrans::Any, fcut::Any) =
      BLDictionary(ftrans_analyse(ftrans), fcut_analyse(fcut)...)



# ------------ Saving and Load Dictionaries

Dict(D::BLDictionary) = Dict( "id" => "BLDictionary", "s" => D.s )

BLDictionary(D::Dict) = BLDictionary(D["s"]...)
Base.convert(::Val{:BLDictionary}, D::Dict) = BLDictionary(D)

# ==================================================================
#           Polynomials of Invariants
# ==================================================================


@pot struct NBody{N, M, T, TD} <: NBodyFunction{N}
   t::VecTup{M}               # tuples M = #edges + 1
   c::Vector{T}               # coefficients
   D::TD                      # BLDictionary (or nothing)
   valN::Val{N}               # encodes that this is an N-body term
end

==(V1::NBody, V2::NBody) = ( (V1.t == V2.t) && (V1.c == V2.c) && (V1.D == V2.D) )


"""
`struct NBody`  (N-Body Basis Function)

A struct storing the information for a pure N-body potential, i.e., containing
*only* terms of a specific body-order. Several `NBody`s can be
combined into an interatomic potential via `NBodyIP`.

### Fields

* `t::Vector{NTuple{M,TI}}` : list of M-tuples containing basis function information
e.g., if M = 3, α = t[1] is a 3-vector then this corresponds to the basis function
`f[α[1]](Q[1]) * f[α[2]](Q[2]) * f[α[3]](Q[3])` where `Q` are the 3-body invariants.

* `c::Vector{T}`: vector of coefficients for the basis functions

* `D`: a `BLDictionary`
"""
NBody

# standad constructor (N can be inferred)
NBody(t::VecTup{K}, c, D) where {K} =
      NBody(t, c, D, Val(edges2bo(K-1)))

# NBody made from a single basis function rather than a collection
NBody(t::Tup, c, D) =
      NBody([t], [c], D)

# collect multiple basis functions represented as NBody's into a single NBody
# (for performance reasons)
NBody(B::Vector{TB}, c, D) where {TB <: NBody} =
      NBody([b.t[1] for b in B], c .* [b.c[1] for b in B], D)

# 1-body term (on-site energy)
NBody(c::Float64) =
      NBody([Tup{0}()], [c], nothing, Val(1))

bodyorder(V::NBody{N}) where {N} = N

dim(V::NBody{N,M}) where {N, M} = M-1

# number of basis functions which this term is made from
length(V::NBody) = length(V.t)

cutoff(V::NBody) = cutoff(V.D)

dictionary(V::NBody) = V.D

function match_dictionary(V::NBody, V1::NBody)
   if V.D != V1.D
      if V.D.s != V1.D.s
         warn("matching two non-matching dictionaries!")
      end
   end
   return NBody(V.t, V.c, V1.D, V.valN)
end

function recover_basis(V::VT) where {VT <: NBody}
   B = Vector{VT}(length(V.t))
   for n = 1:length(V.t)
      B[n] = NBody([ V.t[n] ], [ V.c[n] ], V.D, V.valN)
   end
   return B
end

combine_basis(basis::AbstractVector{TV}, coeffs) where {TV <: NBody} =
      NBody(basis, coeffs, basis[1].D)


function degree(V::NBody)
   if length(V) == 1
      return tdegree(V.t[1])
   end
   error("`degree` is only defined for `NBody` basis functions, length == 1")
end

degree(V::NBody{1}) = 0

# This cannot be quite correct as I am implementing it here; it is probably
#      correct only for the basic invariants that generate the rest
# ispure(V::NBody) = (length(V) == 1) ? ispure(V.valN, V.t[1]) :
#        error("`ispure` is only defined for `NBody` basis functions, length == 1")


function Base.info(B::Vector{T}; indent = 2) where T <: NBody
   ind = repeat(" ", indent)
   println(ind * "body-order = $(bodyorder(B[1]))")
   println(ind * "    length = $(length(B))")
   if bodyorder(B[1]) > 1
      println(ind * " transform = $(B[1].D.s[1])")
      println(ind * "    cutoff = $(B[1].D.s[2])")
   end
end

# -------------- Infrastructure to read/write NBody  --------


Dict(V::NBody{N}) where {N} =
   Dict("id" => "NBody",
        "t" => V.t, "c" => V.c, "D" => Dict(V.D), "N" => N)

function NBody(D::Dict)
   N = D["N"]
   t = [ tuple(ti...) for ti in D["t"] ]
   c = Vector{Float64}(D["c"])
   if N == 1
      return NBody(D["t"], D["c"], nothing, Val(1))
   else
      return NBody(D["t"], D["c"], BLDictionary(D["D"]), Val(N))
   end
end

Base.convert(::Val{:NBody}, D::Dict) = NBody(D)


# ---------------  evaluate the n-body terms ------------------

# a tuple α = (α1, …, α6, α7) means the following:
# with f[0] = 1, f[1] = I7, …, f[5] = I11 we construct the basis set
#   f[α7] * g(I1, …, I6)
# this means, that gen_tuples must generate 7-tuples instead of 6-tuples
# with the first 6 entries restricted by degree and the 7th tuple must
# be in the range 0, …, 5

# TODO: explore StaticPolynomials

evaluate(V::NBody{1}) = sum(V.c)

function evaluate(V::NBody, r::SVector{M, T}) where {M, T}
   # @assert ((N*(N-1))÷2 == M == K-1 == dim(V) == M)
   E = zero(T)
   I1, I2 = invariants(V.D, r)         # SVector{NI, T}
   for (α, c) in zip(V.t, V.c)
      E += c * I2[1+α[end]] * monomial(α, I1)
   end
   return E * fcut(V.D, r)
end


function evaluate_d(V::NBody, r::SVector{M, T}) where {M, T}
   E = zero(T)
   dM = zero(SVector{M, T})
   dE = zero(SVector{M, T})
   D = V.D
   I1, I2, dI1, dI2 = invariants_ed(D, r)
   #
   for (α, c) in zip(V.t, V.c)
      m, m_d = monomial_d(α, I1)
      E += c * I2[1+α[end]] * m        # just the value of the function itself
      dM += (c * I2[1+α[end]]) * m_d   # the I2 * ∇m term without the chain rule
      dE += (c * m) * dI2[1+α[end]]  # the ∇I2 * m term
   end
   # chain rule
   for i = 1:length(dI1)   # dI1' * dM
      dE += dM[i] * dI1[i]
   end
   fc, fc_d = fcut_d(D, r)
   return dE * fc + E * fc_d
end


# ==================================================================
#    SPolyNBody
#      an alternative way to store an N-Body polynomial as a
#      StaticPolynomial
# ==================================================================

@pot struct SPolyNBody{N, TD, TP} <: NBodyFunction{N}
   D::TD       # BLDictionary (or nothing)
   P::TP       # a static polynomial
   valN::Val{N}
end

"""
`struct SPolyNBody`  (N-Body Polynomial)

fast evaluation of the outer polynomial using `StaticPolynomials`
"""
SPolyNBody

function evaluate(V::SPolyNBody, r::SVector{M, T}) where {M, T}
   I = vcat(invariants(V.D, r)...)
   E = StaticPolynomials.evaluate(V.P, I)
   return E * fcut(V.D, r)
end

function evaluate_d(V::SPolyNBody, r::SVector{M, T}) where {M, T}
   D = V.D
   # I = vcat(invariants(D, r)...)   # TODO: combine into a single evaluation
   # dI = vcat(invariants_d(D, r)...)
   I1, I2, dI1, dI2 = invariants_ed(D, r)
   I = vcat(I1, I2)
   dI = vcat(dI1, dI2)
   V, dV_dI = StaticPolynomials.evaluate_and_gradient(V.P, I)
   fc, fc_d = fcut_d(D, r)
   return V * fc_d + fc * dot(dI, dV_dI)  # (dI' * dV_dI)
end


function SPolyNBody(V::NBody{N}) where {N}
   M = bo2edges(N)  # number of edges for body-order N
   I1, I2 = invariants(V.D, SVector(ones(M)...))  # how many invariants
   nI1 = length(I1)
   ninvariants = length(I1) + length(I2)
   nmonomials = length(V.c)
   # generate the exponents for the StaticPolynomial
   exps = zeros(Int, ninvariants, nmonomials)
   for (i, α) in enumerate(V.t)  # i = 1:nmonomials
      for (j, a) in enumerate(α[1:end-1])   #  ∏ I1[j]^α[j]
         exps[j, i] = a    # I1[j]^α[j]
      end
      exps[nI1+1+α[end], i] = 1   # I2[α[end]] * (...)
   end
   # generate the static polynomial
   return SPolyNBody(V.D, StaticPolynomials.Polynomial(V.c, exps), V.valN)
end

bodyorder(V::SPolyNBody{N}) where {N} = N

cutoff(V::SPolyNBody) = cutoff(V.D)

fast(Vn::SPolyNBody)  = Vn
fast(Vn::NBody) =  SPolyNBody(Vn)
fast(Vn::NBody{1}) = Vn



# ==================================================================
#           Generate a Basis
# ==================================================================

nedges(::Val{N}) where {N} = (N*(N-1)) ÷ 2

"""
compute the total degree of the polynomial represented by α.
Note that `M = K-1` where `K` is the tuple length while
`M` is the number of edges.
"""
function tdegree(α)
   K = length(α)
   degs1, degs2 = tdegrees(Val(edges2bo(K-1)))
   # primary invariants
   d = sum(α[j] * degs1[j] for j = 1:K-1)
   # secondary invariants
   d += degs2[1+α[end]]
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
`α -> (0 < tdegree(α) <= deg)` i.e. the standard monomial degree. (note this is
the degree w.r.t. lengths, not w.r.t. invariants!) The `tuplebound` function
must be **monotone**, that is, `α,β` are tuples with `all(α .≦ β)` then
`tuplebound(β) == true` must imply that also `tuplebound(α) == true`.
"""
gen_tuples(N, deg; purify = false,
                   tuplebound = (α -> (0 < tdegree(α) <= deg))) =
   gen_tuples(Val(N), Val(nedges(Val(N))+1), deg, purify, tuplebound)

function gen_tuples(vN::Val{N}, vK::Val{K}, deg, purify, tuplebound) where {N, K}
   A = Tup{K}[]
   degs1, degs2 = tdegrees(vN)

   α = @MVector zeros(Int, K)
   α[1] = 1
   lastinc = 1

   while true
      admit_tuple = false
      if α[end] <= length(degs2)-1
         if tuplebound(α)
            admit_tuple = true
         end
      end
      if admit_tuple
         push!(A, SVector(α).data)
         α[1] += 1
         lastinc = 1
      else
         if lastinc == K
            return A
         end
         α[1:lastinc] = 0
         α[lastinc+1] += 1
         lastinc += 1
      end
   end
   error("I shouldn't be here!")
end


"""
* `poly_basis(N, D, deg; tuplebound = ...)`
* `poly_basis(N, strans, scut, deg; tuplebound = ...)`

generates a basis set of
`N`-body functions, with dictionary `D`, maximal degree `deg`; the precise
set of basis functions constructed depends on `tuplebound` (see `?gen_tuples`)
"""
poly_basis(N::Integer, D::BLDictionary, deg; kwargs...) =
   poly_basis(gen_tuples(N, deg; kwargs...), D)

poly_basis(ts::VecTup, D::BLDictionary) = [NBody(t, 1.0, D) for t in ts]

poly_basis(N::Integer, strans::String, scut::String, deg; kwargs...) =
   poly_basis(N, BLDictionary(strans, scut), deg; kwargs...)


# ---------------------- auxiliary type to


function evaluate_many!(temp, B::Vector{TB}, r::SVector{M, T}
               ) where {TB <: NBody{N}} where {N, M, T}
   E = temp # zeros(T, length(B))
   D = B[1].D
   # it is assumed implicitly that all basis functions use the same dictionary!
   # and that each basis function NBody contains just a single c and a single t
   I1, I2 = invariants(D, r)
   for ib = 1:length(B)
      E[ib] = B[ib].c[1] * I2[1+B[ib].t[1][end]] * monomial(B[ib].t[1], I1)
   end
   fc = fcut(D, r)
   scale!(E, fc)
   return E
end


function evaluate_many_d!(temp, B::Vector{TB}, r::SVector{M, T}
               ) where {TB <: NBody{N}} where {N, M, T}
   E, dM, dE, dEfinal = temp
   fill!(E, 0.0)     # size (nB,)
   fill!(dE, 0.0)    # size (M, nB)
   fill!(dM, 0.0)    # size (M, nB)
   nB = length(B)

   D = B[1].D
   # it is assumed implicitly that all basis functions use the same dictionary!
   # and that each basis function NBody contains just a single c and a single t
   I1, I2, dI1, dI2 = invariants_ed(D, r)
   for ib = 1:nB    # (ib, b) in enumerate(B)
      α = B[ib].t[1]
      c = B[ib].c[1]
      m, m_d = monomial_d(α, I1)
      E[ib] += c * I2[1+α[end]] * m        # just the value of the function itself
      for t = 1:M
         dM[t,ib] += (c * I2[1+α[end]]) * m_d[t]   # the I2 * ∇m term without the chain rule
         dE[t,ib] += (c * m) * dI2[1+α[end]][t]  # the ∇I2 * m term
      end
   end
   # chain rule
   fc, fc_d = fcut_d(D, r)
   for ib = 1:nB
      for i = 1:M, t = 1:M  # dE[ib] += dI1' * dM[ib]
         dE[t,ib] += dI1[i][t] * dM[i,ib]
      end
      for t = 1:M
         dE[t,ib] = dE[t,ib] * fc + E[ib] * fc_d[t]
      end
   end
   # write into an output vector
   for i = 1:nB, t = 1:M
      dEfinal[i][t] = dE[t, i]
   end
   return dEfinal
end


include("poly_regularise.jl")


end # module


# # ----------------- some simplified access functions ------------------
#
# evaluate(V::NBodyFunction{2}, r::Number) = evaluate(V, SVector(r))
#
# evaluate_d(V::NBodyFunction{2}, r::Number) = evaluate_d(V, SVector(r))[1]
#
# evaluate_dd(V::NBodyFunction{2}, r::Number) =
#       ((@D V(r+1e-5)) - (@D V(r-1e-5))) / 1e-5
#
# evaluate(V::NBodyFunction{3}, r1::Number, r2::Number, r3::Number) =
#       evaluate(V, SVector(r1, r2, r3))



# # =============== Experimental:
# #   evaluate NBodyIP
#
# (V::NBodyIP)(args...) = evaluate(V, args...)
#
# evaluate(V::NBodyIP, r::Number) = evaluate(V::NBodyIP, SVector(r))
#
# evaluate(V::NBodyIP, r1::T, r2::T, r3::T) where {T <: Number} =
#       evaluate(V::NBodyIP, SVector(r1, r2, r3))
#
# function evaluate(V::NBodyIP, r::SVector{N, T}) where {N, T}
#    v = zero(T)
#    for Vn in V.orders
#       if bo2edges(bodyorder(Vn)) == N
#          v += Vn(r)
#       end
#    end
#    return v
# end
