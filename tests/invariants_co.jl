using StaticArrays, BenchmarkTools

const PA2= @SMatrix [0 1 1 1 1 1 1 0 0 0 ; 0 0 1 1 1 0 0 1 1 0 ; 0 0 0 1 0 1 0 1 0 1 ; 0 0 0 0 0 0 1 0 1 1 ; 0 0 0 0 0 1 1 1 1 0 ; 0 0 0 0 0 0 1 1 0 1 ; 0 0 0 0 0 0 0 0 1 1 ; 0 0 0 0 0 0 0 0 1 1 ; 0 0 0 0 0 0 0 0 0 1 ; 0 0 0 0 0 0 0 0 0 0 ]

const P4_1 = @SVector [1,1,1,2,1,1,1,2,2,3,4,3,4,2,3,4,5,5,6,7,]
const P4_2 = @SVector [2,2,3,3,5,5,6,5,5,6,7,6,7,8,8,9,6,8,8,9,]
const P4_3 = @SVector [4,3,4,4,7,6,7,9,8,10,10,8,9,9,10,10,7,9,10,10,]

const P6_1 = @SVector [1,1,1,1,1,1,1,1,1,2,2,2,1,1,1,1,1,1,2,2,3,4,3,4,2,2,3,4,3,4,2,2,3,4,3,4,1,1,1,2,2,3,3,2,2,1,1,1,4,3,2,4,3,4,3,2,2,1,1,1,]
const P6_2 = @SVector [2,2,2,2,3,3,2,2,3,3,3,3,5,5,5,5,6,6,5,5,6,7,6,7,5,5,6,6,5,5,7,6,7,6,5,5,4,3,2,4,3,4,4,3,4,2,3,4,5,5,5,5,5,6,7,6,7,5,6,7,]
const P6_3 = @SVector [3,4,3,4,4,4,3,4,4,4,4,4,6,7,6,7,7,7,8,9,8,8,9,8,7,6,7,7,6,7,8,8,8,9,8,9,5,5,6,5,5,6,7,6,7,8,8,9,6,6,6,8,8,8,9,8,9,8,8,9,]
const P6_4 = @SVector [10,10,9,8,9,8,7,6,5,7,6,5,10,10,9,8,9,8,10,10,9,9,10,10,8,9,8,9,10,10,9,9,10,10,10,10,6,7,7,8,9,8,9,10,10,9,10,10,7,7,7,9,9,10,10,10,10,9,10,10,]

const P8_1 = @SVector [1,1,1,1,1,1,1,1,1,2,2,3,4,3,4,2,3,4,1,1,1,2,2,2,2,3,3,1,1,1,]
const P8_2 = @SVector [2,2,2,2,2,2,5,5,5,5,5,5,5,6,6,5,6,7,3,4,2,3,4,3,4,4,4,2,3,4,]
const P8_3 = @SVector [3,3,3,3,3,3,6,6,6,6,7,6,7,7,7,8,8,8,5,5,5,5,5,6,7,6,7,5,6,7,]
const P8_4 = @SVector [4,4,4,4,4,4,7,7,7,8,8,8,9,8,9,9,9,9,6,6,6,8,8,8,9,8,9,8,8,9,]
const P8_5 = @SVector [8,9,10,6,7,5,8,9,10,9,9,10,10,10,10,10,10,10,7,7,7,9,9,10,10,10,10,9,10,10,]

include("fast_monomials.jl")

function invariants(x1::SVector{10, T}) where {T}
    x2 = x1.*x1
    x3 = x2.*x1
    x4 = x3.*x1
    x5 = x4.*x1
    x6 = x5.*x1

    P1 = sum(x1)
    P2 = dot(x1, PA2 * x1)
    P3 = sum(x2)
    P4 = dot(x1[P4_1].* x1[P4_2],x1[P4_3])
    P5 = sum(x3)
    P6 = dot(x1[P6_1].* x1[P6_2],x1[P6_3].* x1[P6_4])
    P7 = sum(x4)
    P8 = dot(x1[P8_1].* x1[P8_2], x1[P8_3].* x1[P8_4].* x1[P8_5])
    P9 = sum(x5)
    P10 = sum(x6)
    return SVector(P1, P2, P3, P4, P5, P6, P7, P8, P9, P10)
end

function invariants2(x1::SVector{10, T}) where {T}
    x2 = x1.*x1
    x3 = x2.*x1

    P1 = sum(x1)
    P2 = dot(x1, PA2 * x1)
    P3 = sum(x2)
    P4 = fmon(x1, x1, x2, P4_1, P4_2, P4_3)
    P5 = sum(x3)
    P6 = fmon(x1, x1, x1, x1, P6_1, P6_2, P6_3, P6_4)
    P7 = dot(x2,x2)
    P8 = fmon(x1, x1, x1, x1, x1, P8_1, P8_2, P8_3, P8_4, P8_5)
    P9 = dot(x2,x3)
    P10 = dot(x3,x3)

    return SVector(P1, P2, P3, P4, P5, P6, P7, P8, P9, P10)
end

x = @SVector rand(10)
@btime invariants($x)
@btime invariants2($x)
