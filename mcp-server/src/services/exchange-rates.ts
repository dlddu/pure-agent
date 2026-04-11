import { S3Client, ListObjectsV2Command, GetObjectCommand } from "@aws-sdk/client-s3";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import type {
  ExchangeRatesServiceOptions,
  IExchangeRatesService,
} from "./types.js";

const EXCHANGE_RATES_PREFIX = "gold/exchange_rates";
const ASSUME_ROLE_SESSION_NAME = "mcp-exchange-rates";
const MAX_RANGE_MONTHS = 120;
// Refresh credentials when they are within this many ms of expiring.
const CREDENTIAL_REFRESH_MARGIN_MS = 5 * 60 * 1000;

interface CachedCredentials {
  accessKeyId: string;
  secretAccessKey: string;
  sessionToken: string;
  /** Epoch millis at which the credentials expire. */
  expiresAtMs: number;
}

export class ExchangeRatesService implements IExchangeRatesService {
  private readonly bucket: string | undefined;
  private readonly region: string | undefined;
  private readonly roleArn: string | undefined;
  private readonly configured: boolean;

  private stsClient: STSClient | undefined;
  private s3Client: S3Client | undefined;
  private cachedCreds: CachedCredentials | undefined;

  constructor(options: ExchangeRatesServiceOptions) {
    this.bucket = options.bucket;
    this.region = options.region;
    this.roleArn = options.roleArn;
    this.configured = Boolean(this.bucket && this.region && this.roleArn);
  }

  async listByDateRange(startDate: string, endDate: string): Promise<string[]> {
    this.assertConfigured();
    if (startDate > endDate) {
      throw new Error("start_date must be <= end_date");
    }
    const months = enumerateMonths(startDate, endDate);
    if (months.length > MAX_RANGE_MONTHS) {
      throw new Error(`Date range too large: ${months.length} months (max ${MAX_RANGE_MONTHS})`);
    }

    const s3 = await this.getS3Client();
    const keys: string[] = [];
    for (const { year, month } of months) {
      const prefix = `${EXCHANGE_RATES_PREFIX}/year=${year}/month=${month}/`;
      let continuationToken: string | undefined;
      do {
        const res = await s3.send(
          new ListObjectsV2Command({
            Bucket: this.bucket!,
            Prefix: prefix,
            ContinuationToken: continuationToken,
          }),
        );
        for (const obj of res.Contents ?? []) {
          if (obj.Key) keys.push(obj.Key);
        }
        continuationToken = res.IsTruncated ? res.NextContinuationToken : undefined;
      } while (continuationToken);
    }
    return keys;
  }

  async getObject(key: string): Promise<Uint8Array> {
    this.assertConfigured();
    const s3 = await this.getS3Client();
    const res = await s3.send(
      new GetObjectCommand({ Bucket: this.bucket!, Key: key }),
    );
    if (!res.Body) {
      throw new Error(`Empty response body for s3://${this.bucket}/${key}`);
    }
    // AWS SDK v3 streaming body exposes transformToByteArray()
    return await (res.Body as { transformToByteArray: () => Promise<Uint8Array> }).transformToByteArray();
  }

  private assertConfigured(): void {
    if (!this.configured) {
      throw new Error(
        "Exchange rates service is not configured: set AWS_S3_BUCKET, AWS_REGION, EXCHANGE_RATES_ROLE_ARN",
      );
    }
  }

  private async getS3Client(): Promise<S3Client> {
    const creds = await this.getCredentials();
    if (!this.s3Client) {
      this.s3Client = new S3Client({
        region: this.region!,
        credentials: {
          accessKeyId: creds.accessKeyId,
          secretAccessKey: creds.secretAccessKey,
          sessionToken: creds.sessionToken,
        },
      });
    }
    return this.s3Client;
  }

  private async getCredentials(): Promise<CachedCredentials> {
    const now = Date.now();
    if (this.cachedCreds && this.cachedCreds.expiresAtMs - now > CREDENTIAL_REFRESH_MARGIN_MS) {
      return this.cachedCreds;
    }
    if (!this.stsClient) {
      this.stsClient = new STSClient({ region: this.region! });
    }
    const res = await this.stsClient.send(
      new AssumeRoleCommand({
        RoleArn: this.roleArn!,
        RoleSessionName: ASSUME_ROLE_SESSION_NAME,
      }),
    );
    const creds = res.Credentials;
    if (!creds || !creds.AccessKeyId || !creds.SecretAccessKey || !creds.SessionToken) {
      throw new Error("AssumeRole returned no credentials");
    }
    this.cachedCreds = {
      accessKeyId: creds.AccessKeyId,
      secretAccessKey: creds.SecretAccessKey,
      sessionToken: creds.SessionToken,
      expiresAtMs: creds.Expiration ? creds.Expiration.getTime() : now + 60 * 60 * 1000,
    };
    // Force S3 client to be recreated with the fresh credentials.
    this.s3Client = undefined;
    return this.cachedCreds;
  }
}

export interface YearMonth {
  /** Zero-padded 4-digit year, e.g. "2026". */
  year: string;
  /** Zero-padded 2-digit month, e.g. "04". */
  month: string;
}

/**
 * Return every unique {year, month} pair spanned by the inclusive date range
 * [startDate, endDate]. Both endpoints are YYYY-MM-DD strings.
 */
export function enumerateMonths(startDate: string, endDate: string): YearMonth[] {
  const [sy, sm] = startDate.split("-").map(Number);
  const [ey, em] = endDate.split("-").map(Number);
  const result: YearMonth[] = [];
  let y = sy;
  let m = sm;
  while (y < ey || (y === ey && m <= em)) {
    result.push({
      year: y.toString().padStart(4, "0"),
      month: m.toString().padStart(2, "0"),
    });
    m += 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
  }
  return result;
}
