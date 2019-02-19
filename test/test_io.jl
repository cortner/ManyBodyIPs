using Test
using NBodyIPs
using NBodyIPs.Polys
using NBodyIPs: BondLengthDesc, SpaceTransform, OneBody

##
println("Check (De-)Dictionisation of `BondLengthDesc`")
D = BondLengthDesc("r -> (2.0/r)^3", "(:cos, 6.0, 9.0)")
Ds = Dict(D)
D1 = BondLengthDesc(Ds)
println(@test D1 == D)

##
println("generate some basis functions")
rcuts = [9.2, 6.2, 4.5]   # 9.2
TRANSFORM = "r -> (2.9/r)^3"
CUTOFF = ["(:cos, $(0.66*rcut), $(rcut))" for rcut in rcuts]
B1 = [OneBody(1.0)]
B2 = blpolys(2, TRANSFORM, CUTOFF[1], 12)
B3 = blpolys(3, TRANSFORM, CUTOFF[2], 10)
B4 = blpolys(4, TRANSFORM, CUTOFF[3], 6)
B = [B1; B2; B3; B4]
c = rand(length(B))
IP = NBodyIP(B, c)
println("Check (De-)Dictionisation of `NBodyIP`")
D_IP = Dict(IP)
IP1 = NBodyIP(D_IP)
println(@test Dict(IP1) == D_IP)
println(@test IP1 == IP)

##
# store it as a JSON file and load it again
fname = tempname() * ".json"
save_ip(fname, IP)
IP2, _ = load_ip(fname)
println(@test IP2 == IP)
run(`rm $fname`)
