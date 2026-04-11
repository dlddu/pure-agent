import type {
  GatekeeperServiceOptions,
  ApprovalResult,
  IGatekeeperService,
} from "./types.js";
import type { IoLayer } from "../io.js";
import type { Logger } from "../logger.js";

const noopLogger: Logger = {
  info: () => {},
  warn: () => {},
  error: () => {},
  debug: () => {},
};

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class GatekeeperService implements IGatekeeperService {
  private gatekeeperUrl: string;
  private apiKey: string;
  private userId: string;
  private pollIntervalMs: number;
  private timeoutMs: number;
  private requesterName: string;
  private io: IoLayer;
  private logger: Logger;

  constructor(options: GatekeeperServiceOptions) {
    this.gatekeeperUrl = options.gatekeeperUrl;
    this.apiKey = options.apiKey;
    this.userId = options.userId;
    this.pollIntervalMs = options.pollIntervalMs ?? 3000;
    this.timeoutMs = options.timeoutMs ?? 600000;
    this.requesterName = options.requesterName ?? "pure-agent";
    this.io = options.io;
    this.logger = options.logger ?? noopLogger;
  }

  async requestApproval(externalId: string, context: string): Promise<ApprovalResult> {
    this.logger.info("Requesting approval from gatekeeper", { externalId });

    const postResponse = await this.io.fetch(`${this.gatekeeperUrl}/api/requests`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": this.apiKey,
      },
      body: JSON.stringify({
        externalId,
        context,
        requesterName: this.requesterName,
        userId: this.userId,
      }),
    });

    if (!postResponse.ok) {
      const errorBody = await postResponse.json();
      this.logger.error("Gatekeeper POST failed", {
        status: postResponse.status,
        body: errorBody,
      });
      throw new Error(
        `Gatekeeper POST failed with status ${postResponse.status}: ${JSON.stringify(errorBody)}`,
      );
    }

    const postBody = await postResponse.json();
    const requestId: string = postBody.id;
    this.logger.info("Approval request created, polling for result", {
      requestId,
      externalId,
    });

    const startTime = Date.now();

    while (true) {
      const getResponse = await this.io.fetch(
        `${this.gatekeeperUrl}/api/requests/${requestId}`,
        {
          method: "GET",
          headers: {
            "x-api-key": this.apiKey,
          },
        },
      );

      if (!getResponse.ok) {
        this.logger.error("Gatekeeper GET poll failed", {
          requestId,
          status: getResponse.status,
        });
        throw new Error(
          `Gatekeeper GET failed with status ${getResponse.status}`,
        );
      }

      const getBody = await getResponse.json();
      const status: string = getBody.status;

      if (status === "APPROVED" || status === "REJECTED" || status === "EXPIRED") {
        this.logger.info("Gatekeeper decision received", { requestId, status });
        return { status: status as ApprovalResult["status"], requestId };
      }

      this.logger.debug("Approval still pending, polling again", {
        requestId,
        elapsedMs: Date.now() - startTime,
      });

      await sleep(this.pollIntervalMs);

      const elapsed = Date.now() - startTime;
      if (elapsed >= this.timeoutMs) {
        this.logger.warn("Gatekeeper approval timed out", {
          requestId,
          timeoutMs: this.timeoutMs,
        });
        return { status: "TIMEOUT" };
      }
    }
  }
}
