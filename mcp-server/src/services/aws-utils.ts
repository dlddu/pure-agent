import { S3Client } from "@aws-sdk/client-s3";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import type { S3ClientLike } from "./types.js";

export interface AssumeRoleS3FactoryOptions {
  region: string;
  roleArn: string;
  sessionName: string;
  endpointUrl?: string;
}

/**
 * Create a factory that assumes the given IAM role and returns a fresh
 * S3Client with temporary credentials. Call this once per tool at startup;
 * the returned function is invoked on each request so credentials stay fresh.
 */
export function createAssumeRoleS3Factory(
  options: AssumeRoleS3FactoryOptions,
): () => Promise<S3ClientLike> {
  const { region, roleArn, sessionName, endpointUrl } = options;
  const s3BaseOptions = {
    region,
    ...(endpointUrl && { endpoint: endpointUrl, forcePathStyle: true }),
  };

  return async () => {
    const sts = new STSClient({ region });
    const { Credentials } = await sts.send(
      new AssumeRoleCommand({
        RoleArn: roleArn,
        RoleSessionName: sessionName,
      }),
    );
    if (!Credentials?.AccessKeyId || !Credentials.SecretAccessKey) {
      throw new Error(`STS AssumeRole returned no credentials for ${roleArn}`);
    }
    return new S3Client({
      ...s3BaseOptions,
      credentials: {
        accessKeyId: Credentials.AccessKeyId,
        secretAccessKey: Credentials.SecretAccessKey,
        sessionToken: Credentials.SessionToken,
      },
    });
  };
}
