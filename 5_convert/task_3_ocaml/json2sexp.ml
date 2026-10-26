type json =
  | Null
  | Bool of bool
  | Number of string
  | String of string
  | Array of json list
  | Object of (string * json) list

exception Parse_error of int * string

let parse (s : string) : json =
  let len = String.length s in
  let pos = ref 0 in
  let fail msg = raise (Parse_error (!pos, msg)) in
  let peek () = if !pos < len then Some s.[!pos] else None in
  let advance () = incr pos in
  let rec skip_ws () =
    match peek () with
    | Some (' ' | '\t' | '\n' | '\r') -> advance (); skip_ws ()
    | _ -> ()
  in
  let expect c =
    if peek () = Some c then advance ()
    else fail (Printf.sprintf "expected '%c'" c)
  in
  let literal word value =
    let n = String.length word in
    if !pos + n <= len && String.sub s !pos n = word then (pos := !pos + n; value)
    else fail ("expected " ^ word)
  in
  let parse_string () =
    expect '"';
    let buf = Buffer.create 16 in
    let rec loop () =
      match peek () with
      | None -> fail "unterminated string"
      | Some '"' -> advance ()
      | Some '\\' ->
          advance ();
          (match peek () with
           | Some '"' -> Buffer.add_char buf '"'
           | Some '\\' -> Buffer.add_char buf '\\'
           | Some '/' -> Buffer.add_char buf '/'
           | Some 'b' -> Buffer.add_char buf '\b'
           | Some 'f' -> Buffer.add_char buf '\012'
           | Some 'n' -> Buffer.add_char buf '\n'
           | Some 'r' -> Buffer.add_char buf '\r'
           | Some 't' -> Buffer.add_char buf '\t'
           | Some 'u' when !pos + 4 < len ->
               let code = int_of_string ("0x" ^ String.sub s (!pos + 1) 4) in
               Buffer.add_utf_8_uchar buf (Uchar.of_int code);
               pos := !pos + 4
           | _ -> fail "bad escape sequence");
          advance ();
          loop ()
      | Some c -> Buffer.add_char buf c; advance (); loop ()
    in
    loop ();
    Buffer.contents buf
  in
  let parse_number () =
    let start = !pos in
    let rec loop () =
      match peek () with
      | Some ('0' .. '9' | '-' | '+' | '.' | 'e' | 'E') -> advance (); loop ()
      | _ -> ()
    in
    loop ();
    let text = String.sub s start (!pos - start) in
    match float_of_string_opt text with
    | Some _ -> Number text
    | None -> fail ("bad number " ^ text)
  in
  let rec parse_value () =
    skip_ws ();
    let v =
      match peek () with
      | Some '{' -> parse_object ()
      | Some '[' -> parse_array ()
      | Some '"' -> String (parse_string ())
      | Some 't' -> literal "true" (Bool true)
      | Some 'f' -> literal "false" (Bool false)
      | Some 'n' -> literal "null" Null
      | Some ('-' | '0' .. '9') -> parse_number ()
      | Some c -> fail (Printf.sprintf "unexpected '%c'" c)
      | None -> fail "unexpected end of input"
    in
    skip_ws ();
    v
  and parse_array () =
    expect '[';
    skip_ws ();
    if peek () = Some ']' then (advance (); Array [])
    else
      let rec items acc =
        let v = parse_value () in
        match peek () with
        | Some ',' -> advance (); items (v :: acc)
        | Some ']' -> advance (); Array (List.rev (v :: acc))
        | _ -> fail "expected ',' or ']'"
      in
      items []
  and parse_object () =
    expect '{';
    skip_ws ();
    if peek () = Some '}' then (advance (); Object [])
    else
      let rec members acc =
        skip_ws ();
        let key = parse_string () in
        skip_ws ();
        expect ':';
        let v = parse_value () in
        match peek () with
        | Some ',' -> advance (); members ((key, v) :: acc)
        | Some '}' -> advance (); Object (List.rev ((key, v) :: acc))
        | _ -> fail "expected ',' or '}'"
      in
      members []
  in
  let result = parse_value () in
  if !pos <> len then fail "extra data after JSON value";
  result

let quote s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter
    (function
      | '"' -> Buffer.add_string buf "\\\""
      | '\\' -> Buffer.add_string buf "\\\\"
      | '\n' -> Buffer.add_string buf "\\n"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let symbol key =
  let ok = function 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' -> true | _ -> false in
  if key <> "" && String.for_all ok key then key else quote key

let rec flat = function
  | Null -> "nil"
  | Bool b -> string_of_bool b
  | Number n -> n
  | String s -> quote s
  | Array items -> "(" ^ String.concat " " (List.map flat items) ^ ")"
  | Object members ->
      "(" ^ String.concat " " (List.map (fun (k, v) -> "(" ^ symbol k ^ " . " ^ flat v ^ ")") members) ^ ")"

let rec pretty indent v =
  let short = flat v in
  if String.length short + indent <= 70 then short
  else
    let pad = String.make (indent + 1) ' ' in
    match v with
    | Array items ->
        "(" ^ String.concat ("\n" ^ pad) (List.map (pretty (indent + 1)) items) ^ ")"
    | Object members ->
        let member (k, v) =
          let head = "(" ^ symbol k ^ " . " in
          head ^ pretty (indent + 1 + String.length head) v ^ ")"
        in
        "(" ^ String.concat ("\n" ^ pad) (List.map member members) ^ ")"
    | _ -> short

let read_file path =
  let ic = open_in_bin path in
  let text = really_input_string ic (in_channel_length ic) in
  close_in ic;
  text

let () =
  let input = if Array.length Sys.argv > 1 then Sys.argv.(1) else "data.json" in
  let output =
    if Array.length Sys.argv > 2 then Sys.argv.(2)
    else Filename.remove_extension input ^ ".sexp"
  in
  match parse (read_file input) with
  | exception Sys_error msg -> prerr_endline msg; exit 1
  | exception Parse_error (pos, msg) ->
      Printf.eprintf "JSON error at position %d: %s\n" pos msg;
      exit 1
  | json ->
      let text = pretty 0 json ^ "\n" in
      print_string text;
      let oc = open_out output in
      output_string oc text;
      close_out oc;
      Printf.printf "Saved to %s\n" output
