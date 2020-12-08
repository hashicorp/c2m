job "example" {
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

  group "cache" {
    count = 1000

    ephemeral_disk {
      size = 10
    }

    # Disable deployments to reduce scheduling overhead
    update {
      max_parallel = 0
    }


    task "sleep" {
      driver = "docker"

      config {
        image   = "alpine:3.12"
        command = "/bin/sleep"
        args    = ["360000"]
      }

      resources {
        cpu    = 50
        memory = 30
      }

      logs {
        max_files     = 1
        max_file_size = 1
      }
    }
  }
}
