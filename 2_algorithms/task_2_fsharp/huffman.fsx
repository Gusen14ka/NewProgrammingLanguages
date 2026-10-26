type Tree =
    | Leaf of char * int
    | Node of Tree * Tree * int

let weight tree =
    match tree with
    | Leaf (_, w) -> w
    | Node (_, _, w) -> w

let rec build (nodes: Tree list) =
    match List.sortBy weight nodes with
    | [] -> failwith "empty text"
    | [ root ] -> root
    | a :: b :: rest -> build (Node(a, b, weight a + weight b) :: rest)

let rec codes tree prefix =
    match tree with
    | Leaf (c, _) -> [ c, (if prefix = "" then "0" else prefix) ]
    | Node (left, right, _) -> codes left (prefix + "0") @ codes right (prefix + "1")

let rec walk tree bits =
    match tree, bits with
    | Leaf (c, _), _ -> c, bits
    | Node (l, _, _), '0' :: rest -> walk l rest
    | Node (_, r, _), _ :: rest -> walk r rest
    | Node _, [] -> failwith "broken code"

let rec decode root bits acc =
    match root, bits with
    | _, [] -> List.rev acc
    | Leaf (c, _), _ :: rest -> decode root rest (c :: acc)
    | _ ->
        let c, rest = walk root bits
        decode root rest (c :: acc)

let show c =
    match c with
    | ' ' -> "' '"
    | '\n' -> "\\n"
    | _ -> string c

let text =
    match fsi.CommandLineArgs with
    | [| _; path |] when System.IO.File.Exists path -> System.IO.File.ReadAllText path
    | [| _; s |] -> s
    | _ -> "abracadabra, mississippi and a banana"

let freqs = text |> Seq.countBy id |> Seq.toList
let tree = freqs |> List.map Leaf |> build
let table = codes tree "" |> Map.ofList

printfn "Text: %s" (if text.Length > 60 then text.Substring(0, 60) + "..." else text)
printfn ""
printfn "%-6s %6s  %s" "char" "count" "code"
for (c, n) in freqs |> List.sortByDescending snd do
    printfn "%-6s %6d  %s" (show c) n table.[c]

let encoded = text |> Seq.map (fun c -> table.[c]) |> String.concat ""
let original = text.Length * 8
printfn ""
printfn "Encoded: %s" (if encoded.Length > 80 then encoded.Substring(0, 80) + "..." else encoded)
printfn "ASCII size:   %d bits" original
printfn "Huffman size: %d bits" encoded.Length
printfn "Compression:  %.1f%% of original" (100.0 * float encoded.Length / float original)

let decoded = decode tree (List.ofSeq encoded) [] |> Array.ofList |> System.String
printfn "Decoded back equals original: %b" (decoded = text)
