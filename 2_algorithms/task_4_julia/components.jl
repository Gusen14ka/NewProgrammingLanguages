function read_graph(path)
    lines = filter(l -> !isempty(l) && !startswith(l, "#"), strip.(readlines(path)))
    n = parse(Int, lines[1])
    adj = [Int[] for _ in 1:n]
    for line in lines[2:end]
        u, v = parse.(Int, split(line))
        push!(adj[u], v)
        push!(adj[v], u)
    end
    return adj
end

function dfs!(adj, v, visited, component)
    visited[v] = true
    push!(component, v)
    for w in adj[v]
        if !visited[w]
            dfs!(adj, w, visited, component)
        end
    end
end

function components(adj)
    visited = falses(length(adj))
    result = Vector{Vector{Int}}()
    for v in eachindex(adj)
        if !visited[v]
            component = Int[]
            dfs!(adj, v, visited, component)
            push!(result, sort(component))
        end
    end
    return result
end

path = isempty(ARGS) ? joinpath(@__DIR__, "graph.txt") : ARGS[1]
adj = read_graph(path)
comps = components(adj)

println("Graph: ", path)
println("Vertices: ", length(adj), ", edges: ", sum(length.(adj)) ÷ 2)
println("Connected components: ", length(comps))
for (i, c) in enumerate(comps)
    println("  #", i, " (size ", length(c), "): ", join(c, " "))
end
println("Largest component size: ", maximum(length, comps))
