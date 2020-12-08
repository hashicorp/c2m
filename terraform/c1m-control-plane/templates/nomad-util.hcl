data_dir = "/opt/nomad/data"
enable_debug = true

bind_addr = "0.0.0.0"
region = "global"
datacenter = "util"

limits {
    http_max_conns_per_client = 0
}

client {
  enabled = true
  server_join {
    retry_join = [ "provider=aws tag_key=${tag_key} tag_value=auto-join addr_type=public_v4"]
  }
}

tls {
  http = true
  rpc = true
  verify_https_client = true
  ca_file = "/etc/nomad.d/tls/ca_cert.pem"
  cert_file = "/etc/nomad.d/tls/cert.pem"
  key_file = "/etc/nomad.d/tls/key.pem"
}

plugin "raw_exec" {
  config {
    enabled = true
  }
}
