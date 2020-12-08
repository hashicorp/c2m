job "spotwatch" {
  type = "system"
  datacenters = [
    "ap-southeast-1",
    "ca-central-1",
    "eu-central-1",
    "eu-west-1",
    "eu-west-2",
    "eu-west-3",
    "us-east-1",
    "us-east-2",
    "us-west-1",
    "us-west-2",
  ]
   

  group "spotwatch" {
    task "spotwatch" {
      artifact {
        source = "https://nomad-c1m.s3.us-east-2.amazonaws.com/spotwatch"
        destination = "/opt/"
      }

      driver = "raw_exec"
      config {
        command = "/opt/spotwatch"
      }

      env {
        NOMAD_ADDR = "https://127.0.0.1:4646"
        NOMAD_CACERT = "/etc/nomad.d/tls/ca_cert.pem"
        NOMAD_CLIENT_CERT ="/etc/nomad.d/tls/cert.pem"
        NOMAD_CLIENT_KEY = "/etc/nomad.d/tls/key.pem"
        NOMAD_SKIP_VERIFY = "1"
      }
    }
  }
}
