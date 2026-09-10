# TODO

Ideas for later versions of the sandbox in `sandbox/`. Not committed to, just parked.


- **fix the fact that specs rely on mise in the agent**. ask any agent to run rspec and you'll see the issue
- **pi as the coding harness.** Replace Claude Code inside the container with pi.
- **opencode go as the model provider for pi.**
- **speak-like-you-eat or nopus with pi.**
- **A real hostname for the box.** `vince-archive` is only an SSH config alias, so it does not resolve in a browser or in `curl`. A memorable, resolvable name for `192.168.1.200` would make the ports in the 4100 to 4199 range reachable as `http://<name>:<port>` instead of typing the LAN IP. Or maybe Tailscale does this.  

- **Tailscale.** The box is only reachable on the home LAN today. Install Tailscale on the box and the Mac, then point both the `vince-archive` and `vinceworks-sandbox` SSH aliases at the Tailscale name so the sandbox works from anywhere. 
