module Prometheus

import HTTP
import URIs
import JSON3
import StructTypes

export query, queryone, queryrange, queryrangeone, labelvalues
export API

""" Represents a series."""
struct Series
  name::Union{String,Nothing}
  labels::Dict{Symbol,Any}
end

StructTypes.StructType(::Type{Series}) = StructTypes.DictType()
StructTypes.construct(::Type{Series}, v::Dict) = Series(get(v, :__name__, nothing), v)

""" Represents a single timeseries value."""
struct Value
  ts::Float64
  value::String
end

StructTypes.StructType(::Type{Value}) = StructTypes.ArrayType()
StructTypes.construct(::Type{Value}, v::Vector) = Value(v[1], v[2])

""" Represents data returned in response."""
abstract type Data end

struct VectorResult
  metric::Series
  value::Value
end

struct VectorData <: Data
  resultType::String
  result::Vector{VectorResult}
end

struct MatrixResult
  metric::Series
  values::Vector{Value}
end

struct MatrixData <: Data
  resultType::String
  result::Vector{MatrixResult}
end

struct ScalarData <: Data
  resultType::String
  result::Value
end


StructTypes.StructType(::Type{Data}) = StructTypes.AbstractType()
StructTypes.StructType(::Type{VectorData}) = StructTypes.Struct()
StructTypes.StructType(::Type{VectorResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{MatrixData}) = StructTypes.Struct()
StructTypes.StructType(::Type{MatrixResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{ScalarData}) = StructTypes.Struct()
StructTypes.subtypekey(::Type{Data}) = :resultType
StructTypes.subtypes(::Type{Data}) = (vector=VectorData, matrix=MatrixData, scalar=ScalarData)

""" API."""
struct API
  endpoint::URIs.URI
end

API(endpoint::String) = API(URIs.URI(endpoint))

default_api = Ref{API}()

server = get(ENV, "PROMETHEUS", "http://127.0.0.1:9090")
default_api[] = API(joinpath(URIs.URI(server), "api/v1"))

function get_api()
  api = get(default_api, (), nothing)
  @assert api !== nothing
  api
end

function call(expect, api::API, path...; kw...)
  uri = URIs.URI(joinpath(api.endpoint, path...), query=kw)
  resp = HTTP.get(uri)
  @assert resp.status == 200
  res = JSON3.read(resp.body, expect)
  @assert res.status == "success"
  res.data
end

""" Query timeseries."""
query(q::String; api::API=default_api[]) =
  call(QueryResponse, api, "query", query=q).result

queryone(q; api::API=default_api[]) =
  query(q; api=api)[1]

""" Query timeseries range."""
queryrange(q::String; api::API=default_api[]) =
  call(QueryResponse, api, "query_range", query=q).result

queryrangeone(q; api::API=default_api[]) =
  queryrange(q; api=api)[1]

struct QueryResponse
  status::String
  data::Data
end

StructTypes.StructType(::Type{QueryResponse}) = StructTypes.Struct()

""" Label values."""
labelvalues(name::String; api::API=default_api[]) =
  call(ValuesResponse, api, "label", name, "values")

struct ValuesResponse
  status::String
  data::Vector{String}
end

StructTypes.StructType(::Type{ValuesResponse}) = StructTypes.Struct()

""" PromQL Query."""
module Q
include("Q.jl")
end

query(q::Any; api::API=default_api[]) = query(Q.render(convert(Q.Query, q)), api=api)
queryrange(q::Q.Query; api::API=default_api[]) = queryrange(Q.render(q), api=api)

end # module
