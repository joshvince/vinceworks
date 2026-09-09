# TODO

Ideas for later versions of the remote dev environments in `projects/`. Not committed to, just parked.

- **Paseo on the box.** Run the Paseo daemon on `vince-archive` pointed at `/home/josh/projects/<name>`. The paths match inside the containers, so it may work with little glue. If Paseo needs a container API, `systemctl --user enable --now podman.socket` plus `DOCKER_HOST=unix:///run/user/1000/podman/podman.sock` is the lever.
- **pi as the coding harness.** Replace Claude Code inside the container with pi.
- **opencode go as the model provider for pi.**
- **speak-like-you-eat or nopus with pi.**
- **A real hostname for the dev environments.** Reaching a project means typing a LAN IP and a port. `vince-archive` is only an SSH config alias, so it does not resolve in a browser or in `curl`, which also makes `vinceworks projects open` fail. Something memorable and resolvable, per project or per port, would be better than remembering which number belongs to which repo.

- **Tailscale.** The box is only reachable on the home LAN today. Install Tailscale on the box and the Mac so `projects` works from anywhere, and point the `vince-archive` SSH alias at the Tailscale name.
