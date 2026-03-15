import { z } from "zod";
import { defineTool, mcpSuccess, mcpError } from "./tool-utils.js";

const MAX_BODY_SIZE = 100_000;

const WebFetchInputSchema = z.object({
  url: z
    .string()
    .min(1, "URL is required")
    .url("Must be a valid URL")
    .describe("The URL to fetch"),
  method: z
    .enum(["GET", "POST", "PUT", "DELETE"])
    .optional()
    .default("GET")
    .describe("HTTP method"),
  headers: z
    .record(z.string(), z.string())
    .optional()
    .describe("Optional request headers"),
  body: z
    .string()
    .optional()
    .describe("Optional request body"),
});

export const webFetchTool = defineTool({
  name: "web_fetch",
  description: "지정한 URL에 HTTP 요청을 보내고 응답을 반환합니다.",
  schema: WebFetchInputSchema,
  handler: async (args, context, extra) => {
    const { url, method, headers, body } = args;

    const sessionId = await context.services.session.readSessionId();
    if (!sessionId) {
      return mcpError("Session ID not found");
    }

    const requestId = extra?.requestId ?? "unknown";
    const externalId = `${sessionId}:${requestId}`;

    const contextString = JSON.stringify({ url, method, headers, body });
    const approval = await context.services.gatekeeper.requestApproval(externalId, contextString);

    if (approval.status !== "APPROVED") {
      return mcpError(`Web fetch request ${approval.status.toLowerCase()}`);
    }

    const response = await context.fetch(url, { method, headers, body });

    let responseBody = await response.text();
    if (responseBody.length > MAX_BODY_SIZE) {
      responseBody = responseBody.slice(0, MAX_BODY_SIZE);
    }

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
