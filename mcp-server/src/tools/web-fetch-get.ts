import { z } from "zod";
import { defineTool, mcpSuccess, mcpError } from "./tool-utils.js";

const MAX_BODY_SIZE = 100_000;

const WebFetchInputSchema = z.object({
  url: z
    .string()
    .min(1, "URL is required")
    .url("Must be a valid URL")
    .describe("The URL to fetch"),
});

export const webFetchGetTool = defineTool({
  name: "web_fetch_get",
  description: "지정한 URL에 GET 요청을 보내고 응답을 반환합니다.",
  schema: WebFetchInputSchema,
  handler: async (args, context, extra) => {
    const { url } = args;
    const method = "GET";
    const log = context.logger;

    log.info("web_fetch_get called", { url });

    const sessionId = await context.services.session.readSessionId();
    if (!sessionId) {
      log.warn("Session ID not found, aborting web_fetch_get");
      return mcpError("Session ID not found");
    }

    const requestId = extra?.requestId ?? "unknown";
    const externalId = `${sessionId.sessionId}:${requestId}`;

    log.debug("Requesting gatekeeper approval", { externalId });
    const contextString = JSON.stringify({ url, method });
    const approval = await context.services.gatekeeper.requestApproval(externalId, contextString);

    if (approval.status !== "APPROVED") {
      log.warn("Gatekeeper denied web_fetch_get", { status: approval.status, externalId });
      return mcpError(`Web fetch request ${approval.status.toLowerCase()}`);
    }

    log.info("Gatekeeper approved, executing fetch", { url, method });
    const response = await context.io.fetch(url, { method });

    let responseBody = await response.text();
    const truncated = responseBody.length > MAX_BODY_SIZE;
    if (truncated) {
      responseBody = responseBody.slice(0, MAX_BODY_SIZE);
    }

    log.info("web_fetch_get completed", {
      url,
      status: response.status,
      bodyLength: responseBody.length,
      truncated,
    });

    return mcpSuccess({
      success: true,
      status: response.status,
      headers: {
        "content-type": response.headers.get("content-type"),
      },
      body: responseBody,
    });
  },
});
