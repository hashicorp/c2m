job "example" {
  datacenters = ["us-east-1"]

  group "cache" {
    ephemeral_disk { size = 10 }
    count = 1000
    task "sleep" {
      driver = "raw_exec"

      config {
        command = "/bin/sleep"
        args = ["1200"]
      }

      resources {
        cpu    = 20
        memory = 20
      }

      logs {
        max_files     = 1
        max_file_size = 1
      }
    }
  }
}
