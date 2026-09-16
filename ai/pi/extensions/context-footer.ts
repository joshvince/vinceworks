import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { truncateToWidth } from "@earendil-works/pi-tui";

const barWidth = 12;

function formatTokens(tokens: number): string {
	if (tokens >= 1_000_000) return `${(tokens / 1_000_000).toFixed(1)}M`;
	if (tokens >= 1_000) return `${(tokens / 1_000).toFixed(1)}k`;
	return `${tokens}`;
}

function formatCwd(cwd: string): string {
	const home = process.env.HOME;
	return home && cwd.startsWith(home) ? `~${cwd.slice(home.length)}` : cwd;
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", (_event, ctx) => {
		ctx.ui.setFooter((_tui, theme) => ({
			invalidate() {},
			render(width) {
				const usage = ctx.getContextUsage();
				const contextWindow = usage?.contextWindow ?? ctx.model?.contextWindow;
				let contextLine: string;
				if (!contextWindow || typeof usage?.tokens !== "number" || typeof usage.percent !== "number") {
					contextLine = `Context ${"░".repeat(barWidth)} ? · ? / ${contextWindow ? formatTokens(contextWindow) : "?"}`;
				} else {
					const filledBlocks = Math.min(barWidth, Math.max(0, Math.round((usage.percent / 100) * barWidth)));
					contextLine = `Context ${"█".repeat(filledBlocks)}${"░".repeat(barWidth - filledBlocks)} ${usage.percent.toFixed(1)}% · ${formatTokens(usage.tokens)} / ${formatTokens(contextWindow)}`;
				}

				const model = ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : "no model";
				const detailsLine = `${model} · ${pi.getThinkingLevel()} · ${formatCwd(ctx.cwd)}`;

				return [
					truncateToWidth(theme.fg("dim", contextLine), width),
					truncateToWidth(theme.fg("dim", detailsLine), width),
				];
			},
		}));
	});
}
