

using StaticArrays

push_str!(ex::Vector{Expr}, s::String) = push!(ex, Meta.parse(s))
append_str!(ex::Vector{Expr}, s::Vector{String}) = append!(ex, Meta.parse.(s))


# univariate monomial
@inline _m1(α::Number, x::T) where {T <: Number} =
      (@fastmath x^α)

# univariate monomial derivative
@inline _m1d(α::Number, x::T) where {T <: Number} =
      α == 0 ? zero(T) : (@fastmath α * x^(α-1))


function monomial(α, x::SVector{K, T}) where {K, T}
   m = one(T)
   for i = 1:K
      @inbounds m *= _m1(α[i], x[i])
   end
   return m
end


@generated function monomial_d(α, x::SVector{K, T}) where {K, T}
   exprs = Expr[]
   # @assert length(α) >= K
   # evaluate the scalar monomials
   #  f = SVector{...}( x[1]^α[1], ...)
   # df = SVector{...}( α[1] * x[1]^(α[1]-1), ...)
   ex_f = "f = @SVector $T["
   ex_df = "df = @SVector $T["
   for i = 1:K
      ex_f  *= " _m1(α[$i], x[$i]), "
      ex_df *= "_m1d(α[$i], x[$i]), "
   end
   ex_f  =  ex_f[1:end-2] * "]"
   ex_df = ex_df[1:end-2] * "]"

   push_str!(exprs, ex_f)
   push_str!(exprs, ex_df)
   push_str!(exprs, "m = 1.0")
   for j = 1:K
      push_str!(exprs, "m *= f[$j]")
   end

   # evaluate the derivative
   for i = 1:K
      push_str!(exprs, "dm_$i = 1.0")
      for j = 1:K
         if i == j
            push_str!(exprs, "dm_$i *= df[$j]")
         else
            push_str!(exprs, "dm_$i *= f[$j]")
         end
      end
   end
   ex_dm = "m_d = @SVector $T["
   for i = 1:K
      ex_dm *= "dm_$i, "
   end
   ex_dm = ex_dm[1:end-2] * "]"
   push_str!(exprs, ex_dm)

   quote
      $(Expr(:meta, :inline))
      @inbounds $(Expr(:block, exprs...))
      return m, m_d
   end
end
