

"""
`invariants(r::SVector{M,T}) -> SVector` : computes the invariant descriptors as a function of the
lengths in a simplex. The order is lexicographical, i.e.,

* 2-body: `r::SVector{1}`
* 3-body: `r::SVector{3}`, order is irrelevant, but `r = [r12, r13, r23]`
* 4-body: `r::SVector{6}`, order is `r = [r12, r13, r14, r23, r24, r34]`
* n-body: `r::SVector{n*(n-1)/2}`, ...

The first `n*(n-1)/2` invariants are the primary invariants; the remainind
ones are the secondary invariants.
"""
function invariants end

"""
`invariants(r::SVector{M,T}) -> SMatrix` : computes the jacobian of
`invariants`
"""
function invariants_d end

"""
`degrees(::Val{N})` where `N` is the body-order returns a
tuple of polynomials degrees corresponding to the degrees of the
individual invariants.  E.g. for 3-body, the invariants are
r1 + r2 + r3, r1 r2 + r1 r3 + r2 r3, r1 r2 r3, and the corresponding
degrees are `(1, 2, 3)`.
"""
function degrees end

"""
`bo2edges(N)` : bodyorder-to-edges
"""
bo2edges(N::Integer) = (N * (N-1)) ÷ 2

"""
`edges2bo(M)`: "edges-to-bodyorder", an internal function that translates
the number of edges in a simplex into the body-order
"""
edges2bo(M::Integer) = (M <= 0) ? 1 : round(Int, 0.5 + sqrt(0.25 + 2 * M))


# ------------------------------------------------------------------------
#             2-BODY Invariants
# ------------------------------------------------------------------------

invariants(r::SVector{1, T}) where {T} =
   copy(r), SVector{1, T}(1.0)

invariants_d(r::SVector{1, T}) where {T} =
   (@SMatrix [one(T)]), (@SMatrix [zero(T)])

degrees(::Val{2}) = (1,), (0,)

# ------------------------------------------------------------------------
#             3-BODY Invariants
# ------------------------------------------------------------------------

# the 1.0 is a "secondary invariant"
invariants(r::SVector{3, T}) where {T} =
      (@SVector T[ r[1]+r[2]+r[3],
                   r[1]*r[2] + r[1]*r[3] + r[2]*r[3],
                   r[1]*r[2]*r[3] ]),
      (@SVector T[ 1.0 ])


invariants_d(  r::SVector{3, T}) where {T} =
      (@SMatrix T[ 1.0        1.0         1.0;
                   r[2]+r[3]  r[1]+r[3]   r[1]+r[2];
                   r[2]*r[3]  r[1]*r[3]   r[1]*r[2] ]),
      (@SMatrix T[ 0.0        0.0         0.0  ])

degrees(::Val{3}) = (1, 2, 3), (0,)


# ------------------------------------------------------------------------
#             4-BODY Invariants
#
# this implementation is based on
#    Schmelzer, A., Murrell, J.N.: The general analytic expression for
#    S4-symmetry-invariant potential functions of tetra-atomic homonuclear
#    molecules. Int. J. Quantum Chem. 28, 287–295 (1985).
#    doi:10.1002/qua.560280210
#
# ------------------------------------------------------------------------
# TODO: reorder to obtain increasing degree?

degrees(::Val{4}) = (1, 2, 3, 4, 2, 3), (0, 3, 4, 5, 6, 9)


const A = @SMatrix [0 1 1 1 1 0
                    1 0 1 1 0 1
                    1 1 0 0 1 1
                    1 1 0 0 1 1
                    1 0 1 1 0 1
                    0 1 1 1 1 0]

function invariants(x::SVector{6, T}) where {T}
   x2 = x.*x
   x3 = x2.*x
   x4 = x3.*x

   I1 = sum(x)
   I2 = x[1]*x[6] + x[2]*x[5] + x[3]*x[4]
   I3 = sum(x2)
   I4 = x[1]*x[2]*x[3] + x[1]*x[4]*x[5] + x[2]*x[4]*x[6] + x[3]*x[5]*x[6]
   I5 =  sum(x3)
   I6 = sum(x4)

   Ax = A*x
   PV1 = dot(x2, Ax)
   PV2 = dot(x3, Ax)
   PV3 = dot(x4, x)
   I11 = PV1 * PV1
   I12 = PV2 * PV3

   return SVector(I1, I2, I3, I4, I5, I6),
          SVector(one(T), PV1, PV2, PV3, I11, I12)
end

function invariants_d(x::SVector{6, T}) where {T}
   x2 = x.*x
   x3 = x2.*x
   x4 = x3.*x
   o = @SVector ones(6)
   z = @SVector zeros(6)
   ∇I2 = @SVector [x[6], x[5], x[4], x[3], x[2], x[1]]
   ∇I4 = @SVector [ x[2]*x[3]+x[4]*x[5],
                    x[1]*x[3]+x[4]*x[6],
                    x[1]*x[2]+x[5]*x[6],
                    x[1]*x[5]+x[2]*x[6],
                    x[1]*x[4]+x[3]*x[6],
                    x[2]*x[4]+x[3]*x[5] ]
   Ax = A*x
   PV1 = dot(x2, Ax)
   PV2 = dot(x3, Ax)
   PV3 = dot(x4, x)
   ∇PV1 = A * x2 + 2 * (x .* Ax)
   ∇PV2 = A * x3 + 3 * (x2 .* Ax)
   ∇PV3 = 5 * x4

   return hcat(o, ∇I2, 2*x, ∇I4, 3*x2, 4*x3, z, ∇PV1, ∇PV2,
               ∇PV3, 2*PV1*∇PV1, PV3*∇PV2 + PV2*∇PV3)'
end


# import StaticPolynomials
# using DynamicPolynomials: @polyvar
#
# @polyvar Q1 Q2 Q3 Q4 Q5 Q6
#
# const INV6Q = StaticPolynomials.system(
#    [  Q1,
#       Q2^2 + Q3^2 + Q4^2,
#       Q2 * Q3 * Q4,
#       Q3^2 * Q4^2 + Q2^2 * Q4^2 + Q2^2 * Q3^2,
#       Q5^2 + Q6^2,
#       Q6^3 - 3*Q5^2 * Q6,
#       1.0,
#       Q6 * (2*Q2^2 - Q3^2 - Q4^2) + √3 * Q5 * (Q3^2 - Q4^2),
#       (Q6^2 - Q5^2) * (2*Q2^2 - Q3^2 - Q4^2) - 2 * √3 * Q5 * Q6 * (Q3^2 - Q4^2),
#       Q6 * (2*Q3^2 * Q4^2 - Q2^2 * Q4^2 - Q2^2 * Q3^2) + √3 * Q2 * (Q2^2 * Q4^2 - Q2^2 * Q3^2),
#       (Q6^2 - Q5^2)*(2*Q3^2*Q4^2 - Q2^2*Q4^2 -Q2^2*Q3^2) - 2*√3 * Q5 * Q6 * (Q2^2*Q4^2 - Q2^2*Q3^2),
#       (Q3^2 - Q4^2) * (Q4^2 - Q2^2) * (Q2^2 - Q3^2) * Q5 * (3*Q6^2 - Q5^2)
#    ])
#
# @inline _invQ6_2_(Q::SVector{6}) = StaticPolynomials.evaluate(INV6Q, Q)
# @inline _invQ6_2_d(Q::SVector{6}) = StaticPolynomials.jacobian(INV6Q, Q)
#
# @inline function invariants_d(r::SVector{6, T}) where {T}
#    J12 = _invQ6_2_d(R2Qxr2ρ * r) * R2Qxr2ρ
#    I1 = @SVector [1,2,3,4,5,6]
#    I2 = @SVector [7,8,9,10,11,12]
#    return J12[I1,:], J12[I2,:]
# end


# ------------------------------------------------------------------------
#             5-BODY Invariants
# ------------------------------------------------------------------------

#Invariants up to degree 7 only.
# COPIED FROM SLACK:
# For the 5-body, if I am right, the number of primary invariants is 10 with
# degrees : [ 1, 2, 2, 3, 3, 4, 4, 5, 5, 6 ]. The number of secondary for each
# degree (starting from 0) is [ 1, 0, 0, 2, 5, 8, 15, 23, 33, 46 ] which means
# in total 133 secondary of degree less than 9. That’s quite a lot. Some of
# them have very long expressions.

degrees(::Val{5}) = ( 1, 2, 2, 3, 3, 4, 4, 5, 5, 6), (0, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6,
6, 6, 6, 6, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7,
7)
