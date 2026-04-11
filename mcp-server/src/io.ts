export interface IoLayer {
  fs: {
    writeFile(path: string, data: string, encoding: BufferEncoding): Promise<void>;
    readFile(path: string, encoding: BufferEncoding): Promise<string>;
    access(path: string): Promise<void>;
    stat(path: string): Promise<{ mtimeMs: number }>;
  };
  exec: {
    execFile(
      file: string,
      args: string[],
      options: { cwd: string; timeout: number; maxBuffer: number },
    ): Promise<{ stdout: string; stderr: string }>;
  };
  fetch: typeof globalThis.fetch;
}
