data_dir = "/opt/nomad/data"
enable_debug = true

bind_addr = "0.0.0.0"
region = "global"
datacenter = "${datacenter}"

client {
  enabled = true

  # Limit resources used by client gc
  gc_max_allocs = 300
  gc_parallel_destroys = 1

  options {
    "alloc.rate_limit" = "50"
    "alloc.rate_burst" = "2"
  }

  server_join {
    retry_join = [ "provider=aws tag_key=${tag_key} tag_value=auto-join addr_type=public_v4 region=${cp_region}"]
  }
}

plugin "docker" {
  config {
    gc {
      image       = false
      image_delay = "3m"
      container   = true

      dangling_containers {
        enabled        = false
      }
    }
  }
}

plugin "raw_exec" {
  config {
    enabled = true
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
