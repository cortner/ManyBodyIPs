
using NBodyIPs, StaticArrays, BenchmarkTools, JuLIP, Test, Profile

# using JuLIP.Potentials: evaluate, evaluate_d
# using NBodyIPs: BondLengthDesc, BondAngleDesc, invariants, invariants_d, descriptor,
#                bo2angles, bo2edges
using NBodyIPs.Polys

TRANSFORM = PolyTransform(3, 2.9) # "r -> (2.9/r)^3"
DEGREES = [18, 14, 12, 10]
RCUT = [7.0, 5.80, 4.5, 4.1]

function random_ip(DT)
   DD = [ DT(TRANSFORM, CosCut(rcut-1.0, rcut))  for rcut in RCUT ]

   # 2-body potential
   B2 = nbpolys(2, DD[1], DEGREES[1])
   c = rand(length(B2))
   V2 = NBPoly(B2, c, DD[1])
   V2sp = StNBPoly(V2)

   # 3-body potential
   B3 = nbpolys(3, DD[2], DEGREES[2])
   c = rand(length(B3))
   V3 = NBPoly(B3, c, DD[2])
   V3sp = StNBPoly(V3)

   # 4-body potential
   B4 = nbpolys(4, DD[3], DEGREES[3])
   c = rand(length(B4))
   V4 = NBPoly(B4, c, DD[3])
   V4sp = StNBPoly(V4)

   # 5-body potential
   B5 = nbpolys(5, DD[4], DEGREES[4])
   c = rand(length(B5))
   V5 = NBPoly(B5, c, DD[4])
   V5sp = StNBPoly(V5)

   IP = NBodyIP([V2, V3, V4, V5])
   IPf = NBodyIP([V2sp, V3sp, V4sp, V5sp])

   return IP, IPf
end

_, IPf = random_ip(BondLengthDesc)
at = rattle!(bulk(:W, cubic=true) * 3, 0.01)
energy(IPf, at)
forces(IPf, at)
at = rattle!(bulk(:W, cubic=true) * 10, 0.01)
@info("Energy")
@time energy(IPf, at)
@time energy(IPf, at)
@info("Forces")
@time forces(IPf, at)
@time forces(IPf, at)


# test correctness first
IP_bl, _ = random_ip(BondLengthDesc)
IP_cl = NBodyIPs.Experimental.faster_blpot(IP_bl)

at = rattle!(bulk(:W, cubic=true) * 10, 0.01)
# set_pbc!(at, false)

V2_bl = IP_bl.components[1]
V2_cl = IP_cl.components[1]
@test energy(V2_bl, at) ≈ energy(V2_cl, at)

V3_bl = IP_bl.components[2]
V3_cl = IP_cl.components[2]
@test energy(V3_bl, at) ≈ energy(V3_cl, at)

V4_bl = IP_bl.components[3]
V4_cl = IP_cl.components[3]
@test energy(V4_bl, at) ≈ energy(V4_cl, at)


for DT in [BondLengthDesc, ClusterBLDesc]
   println("-----------------------------------------------------------")
   println(" Testing StaticPolynomials with D = $(DT)")
   println("-----------------------------------------------------------")

   DD = [ DT(TRANSFORM, CosCut(rcut-1, rcut))  for rcut in RCUT ]

   # 2-body potential
   B2 = nbpolys(2, DD[1], DEGREES[1])
   c = rand(length(B2))
   V2 = NBPoly(B2, c, DD[1])
   V2sp = StNBPoly(V2)

   # 3-body potential
   B3 = nbpolys(3, DD[2], DEGREES[2])
   c = rand(length(B3))
   V3 = NBPoly(B3, c, DD[2])
   V3sp = StNBPoly(V3)

   # 4-body potential
   B4 = nbpolys(4, DD[3], DEGREES[3])
   c = rand(length(B4))
   V4 = NBPoly(B4, c, DD[3])
   V4sp = StNBPoly(V4)

   IP = NBodyIP([V2, V3, V4])
   IPf = NBodyIP([V2sp, V3sp, V4sp])

   println("Neighbourlist")
   @time neighbourlist(at, cutoff(V2_bl))
   @time neighbourlist(at, cutoff(V2_bl))
   println("Dynamic Polynomials")
   @time energy(IP, at)
   @time energy(IP, at)
   @time forces(IP, at)
   @time forces(IP, at)
   println("Static Polynomials")
   @time energy(IPf, at)
   @time energy(IPf, at)
   @time forces(IPf, at)
   @time forces(IPf, at)
end
