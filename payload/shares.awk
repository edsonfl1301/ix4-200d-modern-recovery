# Only translate data shares and explicit ACL directives; never import globals.
function flush( k) {
  if (name != "" && path ~ /^\/mnt\/pools\//) {
    sub(/^\/mnt\/pools\//,"/srv/pools/",path)
    print "\n[" name "]\n path = " path "\n guest ok = no\n read only = yes\n valid users = unuser"
    for (k in opts) print " " k " = " opts[k]
    print " wide links = no"
    count++
  }
  delete opts; name=""; path=""
}
/^[[:space:]]*\[/ {
  flush(); name=$0; sub(/^[[:space:]]*\[/,"",name); sub(/\].*$/,"",name)
  if (tolower(name) ~ /^(global|printers|homes)$/) name=""
  next
}
name!="" && /^[[:space:]]*[^#;].*=/ {
  p=index($0,"="); k=tolower(substr($0,1,p-1)); v=substr($0,p+1)
  gsub(/^[[:space:]]+|[[:space:]]+$/,"",k); gsub(/^[[:space:]]+|[[:space:]]+$/,"",v)
  if (k=="path") path=v
  if(k ~ /^(valid users|invalid users|write list|read list|read only|writeable|writable|create mask|directory mask|create mode|directory mode|nt acl support|dos filemode|store dos attributes|follow symlinks|max connections|browseable|browsable)$/) opts[k]=v
}
END { flush(); if(count==0) exit 2 }
