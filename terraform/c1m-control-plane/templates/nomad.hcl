data_dir = "/opt/nomad/data"
enable_debug = true

bind_addr = "0.0.0.0"
region = "global"
datacenter = "${datacenter}"
log_level = "DEBUG"

# Disable rpc connection limit since we're using NATs
limits {
    http_max_conns_per_client = 0
    rpc_max_conns_per_client = 0
    rpc_handshake_timeout = "20s"
}

server {
  enabled          = true
  bootstrap_expect = ${cluster_size}
  server_join {
    retry_join = [ "provider=aws tag_key=${tag_key} tag_value=auto-join addr_type=public_v4"]
  }

  # Disable event broker while its still under heavy development
  enable_event_broker = false

  default_scheduler_config {
    scheduler_algorithm = "spread"
  }

  raft_multiplier = 5
}

client {
  enabled = true
  server_join {
    retry_join = [ "provider=aws tag_key=${tag_key} tag_value=auto-join addr_type=public_v4"]
  }
}

telemetry {
  datadog_address = "127.0.0.1:8125"
  collection_interval        = "1s"
  disable_hostname           = true
  prometheus_metrics         = true
  publish_allocation_metrics = false
  publish_node_metrics       = false
}

tls {
  http = true
  rpc = true
  verify_https_client = true
  ca_file = "/etc/nomad.d/tls/ca_cert.pem"
  cert_file = "/etc/nomad.d/tls/cert.pem"
  key_file = "/etc/nomad.d/tls/key.pem"
}
