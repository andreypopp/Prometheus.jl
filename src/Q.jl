import URIs

export series, @series_str, empty, filter, within, offset, at, func, op, literal
export miliseconds, seconds, minutes, hours, days, weeks, years
export milisecond, second, minute, hour, day, week, year
export on, ignoring, groupleft, groupright
export by, without

abstract type Query end
abstract type SimpleQuery <: Query end

(c::Query)(c′) = c(convert(Query, c′))

""" Empty query."""
struct Empty <: SimpleQuery end

empty = Empty()

Base.convert(::Type{SimpleQuery}, ::Nothing) = Empty()
Base.convert(::Type{Query}, ::Nothing) = Empty()

(q::Empty)(o) = o

""" Instant vector selector."""
struct Series <: SimpleQuery
  name::String
end

(q::Series)(::Query) = q
(q::Series)(;kwargs...) = Filter(q, kwargs)

series(s::String) = Series(s)

Base.getproperty(::typeof(series), name::Symbol) = Series(String(name))
Base.getproperty(::typeof(series), name::String) = Series(name)

macro series_str(name); :(Series($name)) end

""" Filter instant vector by labels."""
struct Filter <: SimpleQuery
  base::SimpleQuery
  labels::Dict{Symbol,String}
end

(q::Filter)(o::Query) = Filter(q.base(o), q.labels)

filter(labels::Dict{Symbol,String}) = Filter(nothing, labels)
filter(;labels...) = Filter(nothing, labels)

@enum IntervalUnit miliseconds seconds minutes hours days weeks years

milisecond = miliseconds
second = seconds
minute = minutes
hour = hours
day = days
week = weeks
year = years

Base.:*(val::Int, unit::IntervalUnit) =
  Interval(val, unit)

struct Interval
  value::Int
  unit::IntervalUnit
end

Base.convert(::Type{Interval}, val::Int) = Interval(val, sec)

Base.:*(val::Int, int::Interval) =
  Interval(val * int.value, int.unit)

struct Range <: SimpleQuery
  base::Query
  range::Interval
  resolution::Union{Nothing,Interval}
end

within(range, resolution=nothing) =
  Range(nothing, range, resolution)

(q::Range)(o::Query) = Range(q.base(o), q.range, q.resolution)

""" Offset-modifier."""
struct Offset <: Query
  base::Query
  offset::String
end

(q::Offset)(o::Query) = Offset(q.base(o), q.offset)

offset(offset::String) = Offset(nothing, offset)

""" @-modifier."""
struct At <: Query
  base::Query
  at::Float64
end

at(at::Float64) = At(nothing, at)

(q::At)(o::Query) = At(q.base(o), q.at)

""" Functions."""
struct Func <: Query
  name::String
  args::Vector{Query}
  kwargs::Dict{Symbol,Query}
  by::Union{Nothing,Vector{String}}
  without::Union{Nothing,Vector{String}}
end

(q::Func)(o::Query) = begin
  args = copy(q.args)
  # TODO(andreypopp): is this the right way to prepend aln element?
  prepend!(args, [o])
  Func(q.name, args, q.kwargs, q.by, q.without)
end

func(name::String) = Func(name, Query[], Dict())

func(name::String, args...; by=nothing, without=nothing, kwargs...) =
  Func(name, Query[args...], kwargs, by, without)

by(labels...) = (q::Func) ->
  Func(q.name, q.args, q.kwargs, String[labels...], nothing)
without(labels...) = (q::Func) ->
  Func(q.name, q.args, q.kwargs, nothing, String[labels...])

Base.getproperty(::typeof(func), name::Symbol) =
  (args...; by=nothing, without=nothing, kwargs...) ->
    Func(String(name), Query[args...], kwargs, by, without)
Base.getproperty(::typeof(func), name::String) =
  (args...; by=nothing, without=nothing, kwargs...) ->
    Func(name, Query[args...], kwargs, by, without)

""" Operators."""
struct Op <: Query
  op::String
  lhs::Query
  rhs::Query
  on::Union{Nothing,Vector{String}}
  ignoring::Union{Nothing,Vector{String}}
  groupleft::Union{Nothing,Vector{String}}
  groupright::Union{Nothing,Vector{String}}
end

(q::Op)(::Query) = q

op(op::String, lhs::Query, rhs::Query;
   on=nothing, ignoring=nothing,
   groupleft=nothing, groupright=nothing) = begin
  if isequal(groupleft, true); groupleft=[] end
  if isequal(groupright, true); groupright=[] end
  Op(op, lhs, rhs, on, ignoring, groupleft, groupright)
end

groupleft(labels...) = (q::Op) ->
  Op(q.op, q.lhs, q.rhs, q.on, q.ignoring, String[labels...], nothing)
groupright(labels...) = (q::Op) ->
  Op(q.op, q.lhs, q.rhs, q.on, q.ignoring, nothing, String[labels...])
on(labels...) = (q::Op) ->
  Op(q.op, q.lhs, q.rhs, String[labels...], nothing, q.groupleft, q.groupright)
ignoring(labels...) = (q::Op) ->
  Op(q.op, q.lhs, q.rhs, nothing, String[labels...], q.groupleft, q.groupright)

Base.getproperty(::typeof(op), name::Symbol) =
  (lhs, rhs;
   on=nothing, ignoring=nothing,
   groupleft=nothing, groupright=nothing
  ) -> Op(String(name), lhs, rhs, on, ignoring, groupleft, groupright)
Base.getproperty(::typeof(op), name::String) =
  (lhs, rhs;
   on=nothing, ignoring=nothing,
   groupleft=nothing, groupright=nothing
  ) -> Op(name, lhs, rhs, on, ignoring, groupleft, groupright)

""" Literals (can be either strings or floats)."""
struct Literal <: SimpleQuery
  value::Union{String,Float64}
end

literal(v::Any) = Literal(v)

(q::Literal)(::Query) = q

Base.convert(::Type{Query}, val::Int) = Literal(Float64(val))
Base.convert(::Type{Query}, val::Float64) = Literal(val)
Base.convert(::Type{Query}, val::String) = Literal(val)

""" Render query into string."""
render(v::Any)::String = render(convert(Query, v))
render(q::Series)::String = q.name
render(q::Filter)::String =
  let
    args = (string(k, "=", '"', URIs.escapeuri(v), '"') for (k, v) in q.labels)
    string(render(q.base), "{", join(args, ","), "}")
  end
render(q::Range)::String = let
  range = q.resolution === nothing ?
    render(q.range) :
    string(render(q.range), ":", render(q.resolution))
  string(subrender(q.base), "[$range]")
end
render(q::Offset)::String = "$(subrender(q.base)) offset $(q.offset)"
render(q::At)::String = "$(subrender(q.base)) @ $(string(q.at))"
render(q::Literal)::String = string(q.value)
render(q::Func)::String = begin
  args = []
  for a in q.args; push!(args, render(a)) end
  for (k, a) in q.kwargs; push!(args, string(k, "=", render(a))) end
  string(
         q.name,
         !isnothing(q.by) ? " by ($(render(q.by)))" : "",
         !isnothing(q.without) ? " without ($(render(q.without)))" : "",
         "(", join(args, ","),  ")"
        )
end
render(q::Op)::String =
  string(
         subrender(q.lhs), " ",
         q.op, " ",
         !isnothing(q.on) ? "on($(render(q.on))) " : "",
         !isnothing(q.ignoring) ? "ignoring($(render(q.ignoring))) " : "",
         !isnothing(q.groupleft) ? "group_left($(render(q.groupleft))) " : "",
         !isnothing(q.groupright) ? "group_right($(render(q.groupright))) " : "",
         subrender(q.rhs)
        )

render(xs::Vector{String}) =
  join(xs, ", ")

render(int::Interval)::String =
  string(int.value, render(int.unit))

render(unit::IntervalUnit)::String =
  if unit === miliseconds; "ms"
  elseif unit === seconds; "s"
  elseif unit === minutes; "m"
  elseif unit === hours; "h"
  elseif unit === days; "d"
  elseif unit === weeks; "w"
  elseif unit === years; "y"
  end

subrender(q::Query) =
  let s = render(q)
    if q isa SimpleQuery; s else "($s)" end
  end

struct OpStyle <: Base.BroadcastStyle
end

Base.BroadcastStyle(::Type{<:Query}) =
    OpStyle()

Base.BroadcastStyle(::OpStyle, ::Base.Broadcast.DefaultArrayStyle{0}) =
    OpStyle()

Base.broadcastable(n::Query) =
    n

Base.Broadcast.instantiate(bc::Base.Broadcast.Broadcasted{OpStyle}) =
    bc

Base.copy(bc::Base.Broadcast.Broadcasted{OpStyle}) =
  Op(String(nameof(bc.f)), bc.args[1], bc.args[2],
     nothing, nothing, nothing, nothing)

Base.convert(::Type{Query}, bc::Base.Broadcast.Broadcasted{OpStyle}) =
  Op(String(nameof(bc.f)), bc.args[1], bc.args[2],
     nothing, nothing, nothing, nothing)
