import { describe, it, expect, vi } from "vitest";
import { S3Client } from "@aws-sdk/client-s3";
import { STSClient, AssumeRoleCommand } from "@aws-sdk/client-sts";
import { createAssumeRoleS3Factory } from "./aws-utils.js";

describe("createAssumeRoleS3Factory", () => {
  it("returns a function", () => {
    const factory = createAssumeRoleS3Factory({
      region: "ap-northeast-2",
      roleArn: "arn:aws:iam::123:role/test",
      sessionName: "test-session",
    });
    expect(typeof factory).toBe("function");
  });

  it("calls STS and returns an S3Client with assumed credentials", async () => {
    const mockCreds = {
      AccessKeyId: "AKIA-TEMP",
      SecretAccessKey: "secret-temp",
      SessionToken: "token-temp",
    };

    // Spy on STSClient.prototype.send
    const sendSpy = vi
      .spyOn(STSClient.prototype, "send")
      .mockResolvedValue({ Credentials: mockCreds } as never);

    const factory = createAssumeRoleS3Factory({
      region: "ap-northeast-2",
      roleArn: "arn:aws:iam::123:role/my-role",
      sessionName: "my-session",
    });

    const client = await factory();

    // Verify STS was called with correct AssumeRoleCommand
    expect(sendSpy).toHaveBeenCalledTimes(1);
    const cmd = sendSpy.mock.calls[0][0];
    expect(cmd).toBeInstanceOf(AssumeRoleCommand);
    expect((cmd as AssumeRoleCommand).input).toEqual({
      RoleArn: "arn:aws:iam::123:role/my-role",
      RoleSessionName: "my-session",
    });

    // Returned value is an S3Client
    expect(client).toBeInstanceOf(S3Client);

    sendSpy.mockRestore();
  });

  it("throws when AssumeRole returns no credentials", async () => {
    const sendSpy = vi
      .spyOn(STSClient.prototype, "send")
      .mockResolvedValue({ Credentials: undefined } as never);

    const factory = createAssumeRoleS3Factory({
      region: "ap-northeast-2",
      roleArn: "arn:aws:iam::123:role/bad",
      sessionName: "test",
    });

    await expect(factory()).rejects.toThrow("STS AssumeRole returned no credentials");

    sendSpy.mockRestore();
  });
});
