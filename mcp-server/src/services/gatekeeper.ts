import type {
  GatekeeperServiceOptions,
  ApprovalResult,
  IGatekeeperService,
} from "./types.js";

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class GatekeeperService implements IGatekeeperService {
  private gatekeeperUrl: string;
  private apiKey: string;
  private pollIntervalMs: number;
  private timeoutMs: number;
  private fetch: typeof globalThis.fetch;

  constructor(options: GatekeeperServiceOptions) {
    this.gatekeeperUrl = options.gatekeeperUrl;
    this.apiKey = options.apiKey;
    this.pollIntervalMs = options.pollIntervalMs ?? 2000;
    this.timeoutMs = options.timeoutMs ?? 300000;
    this.fetch = options.fetch;
  }

  async requestApproval(externalId: string): Promise<ApprovalResult> {
    const postResponse = await this.fetch(`${this.gatekeeperUrl}/api/requests`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": this.apiKey,
      },
      body: JSON.stringify({
        externalId,
        context: externalId,
        requesterName: "pure-agent",
      }),
    });

    if (!postResponse.ok) {
      const errorBody = await postResponse.json();
      throw new Error(
        `Gatekeeper POST failed with status ${postResponse.status}: ${JSON.stringify(errorBody)}`,
      );
    }

    const postBody = await postResponse.json();
    const requestId: string = postBody.requestId;

    const startTime = Date.now();

    while (true) {
      const getResponse = await this.fetch(
        `${this.gatekeeperUrl}/api/requests/${requestId}`,
        {
          method: "GET",
          headers: {
            "x-api-key": this.apiKey,
          },
        },
      );

      if (!getResponse.ok) {
        throw new Error(
          `Gatekeeper GET failed with status ${getResponse.status}`,
        );
      }

      const getBody = await getResponse.json();
      const status: string = getBody.status;

      if (status === "APPROVED" || status === "REJECTED" || status === "EXPIRED") {
        return { status: status as ApprovalResult["status"], requestId };
      }

      await sleep(this.pollIntervalMs);

      const elapsed = Date.now() - startTime;
      if (elapsed >= this.timeoutMs) {
        return { status: "TIMEOUT" };
      }
    }
  }
}
