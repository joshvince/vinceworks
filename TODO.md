# TODO

Ideas for later versions of the sandbox in `sandbox/`. Not committed to, just parked.


- **fix the fact that specs rely on mise in the agent**. ask any agent to run rspec and you'll see the issue
- **solve the port assignment issue**. See below for a transcript wiht some ideas
- **pi as the coding harness.** Replace Claude Code inside the container with pi.
- **opencode go as the model provider for pi.**
- **speak-like-you-eat or nopus with pi.**
- **A real hostname for the box.** `vince-archive` is only an SSH config alias, so it does not resolve in a browser or in `curl`. A memorable, resolvable name for `192.168.1.200` would make the ports in the 4100 to 4199 range reachable as `http://<name>:<port>` instead of typing the LAN IP. Or maybe Tailscale does this.  

- **Tailscale.** The box is only reachable on the home LAN today. Install Tailscale on the box and the Mac, then point both the `vince-archive` and `vinceworks-sandbox` SSH aliases at the Tailscale name so the sandbox works from anywhere.
- 


### Port assignment issue
"
ok so lets think again about this port assignation... give me some pragmatic options that should work for most apps, who rely on $PORT ?
16:48


Assuming apps honour PORT (Procfile fixed to ${PORT:-3000})
**Worktree hook writes PORT into `.env`.** `paseo.json` setup runs one shared script from the vinceworks mount, `~/vinceworks/sandbox/worktree-setup`. Script copies secrets from the source checkout and appends `PORT=<free port in range>` to the worktree `.env`. Foreman and dotenv read `.env`, so `bin/dev` from any terminal or agent lands on a published port. Per-repo `paseo.json` shrinks to one line calling the script. Only covers worktrees, not the main checkout, and only apps that load `.env`. Both true for your Rails repos.

16:50
Logic lives in vinceworks, not in paseo.json
. One script in the sandbox, say sandbox/checkout-setup, does the work: copy secrets from the main checkout, pick a free port from the range, write PORT into the worktree 
.env
. Paseo's setup hook becomes a one-line adapter calling it. When pi or anything else replaces Paseo, its hook calls the same script. Swap the adapter, keep the logic.
"
