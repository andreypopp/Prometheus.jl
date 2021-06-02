# Prometheus.jl

**DO NOT USE: EXPERIMENTAL**

Prometheus Query API client and a combinator API to build PromQL queries.


    using Prometheus, Prometheus.Q

    data = query(series."sensor_temp" |> within(1day, 1hour))
