output "generated_secrets" {
  value = {
    for k, v in random_password.random : k => v.result
  }
  sensitive = true
}
