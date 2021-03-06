open Lwt
open Printf
open V1_LWT
open Re_str
 
module Main (C:CONSOLE) (FS:KV_RO) (S:Cohttp_lwt.Server) = struct
 
  let start c fs http =
 
    let read_fs name =
      FS.size fs name
      >>= function
      | `Error (FS.Unknown_key _) -> fail (Failure ("read " ^ name))
      | `Ok size ->
        FS.read fs name 0 (Int64.to_int size)
        >>= function
        | `Error (FS.Unknown_key _) -> fail (Failure ("read " ^ name))
        | `Ok bufs -> return (Cstruct.copyv bufs)
    in
 
    (* Split a URI into a list of path segments *)
    let split_path uri =
      let path = Uri.path uri in
      let rec aux = function
        | [] | [ (Re_str.Text "")] -> []
        | [ (Re_str.Delim "/") ] -> ["index.html"] (*trailing slash*)
        | (Re_str.Text hd)::tl -> hd :: aux tl
        | (Re_str.Delim hd)::tl -> aux tl
      in
      (List.filter (fun e -> e <> "")
        (aux (Re_str.(full_split (regexp_string "/") path))))
    in
 
    let content_type path =
      let open String in
      try
        let idx = String.index path '.' + 1 in
        let rt = String.sub path idx (String.length path - idx) in
        match rt with
        | "js"   -> "application/javascript"
        | "css"  -> "text/css"
        | "html" -> "text/html; charset=utf-8"
        | "json" -> "application/json"
        | "png"  -> "image/png"
        | "xml"  -> "application/atom+xml"
        | _ -> "text/plain"
      with _ -> "text/plain"
    in

    (* dispatch non-file URLs *)
    let rec dispatcher = function
      | [] | [""] -> dispatcher ["index.html"] 
      | segments ->
        let path = String.concat "/" segments in
        (* C.log c (Printf.sprintf "Seeking path %s" path); *)
        try_lwt
          read_fs path
          >>= fun body ->
          S.respond_string ~headers:(Cohttp.Header.of_list ["Content-type", content_type path]) ~status:`OK ~body ()
        with exn ->
          S.respond_not_found ()
    in
 
    (* HTTP callback *)
    let callback conn_id request body =
      let uri = S.Request.uri request in
      dispatcher (split_path uri)
    in
    let conn_closed (_,conn_id) () =
      let cid = Cohttp.Connection.to_string conn_id in
      C.log c (Printf.sprintf "conn %s closed" cid)
    in
    http { S.callback; conn_closed }
 
end
