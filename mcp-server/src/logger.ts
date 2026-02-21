// Synced copy: also exists in export-handler/src/logger.ts — keep both in sync
export interface Logger {
  info(message: string, ...args: unknown[]): void;
  warn(message: string, ...args: unknown[]): void;
  error(message: string, ...args: unknown[]): void;
  debug(message: string, ...args: unknown[]): void;
}

type LogLevel = "info" | "warn" | "error" | "debug";

const isJsonFormat = process.env.LOG_FORMAT === "json";

function formatData(args: unknown[]): unknown | undefined {
  if (args.length === 0) return undefined;
  return args.length === 1 ? args[0] : args;
}

export function createLogger(component: string): Logger {
  if (isJsonFormat) {
    const logJson = (level: LogLevel, message: string, args: unknown[]) => {
      const entry: Record<string, unknown> = {
        timestamp: new Date().toISOString(),
        level,
        component,
        message,
      };
      const data = formatData(args);
      if (data !== undefined) entry.data = data;
      const consoleFn = level === "error" ? console.error : level === "warn" ? console.warn : console.log;
      consoleFn(JSON.stringify(entry));
    };

    return {
      info: (msg, ...args) => logJson("info", msg, args),
      warn: (msg, ...args) => logJson("warn", msg, args),
      error: (msg, ...args) => logJson("error", msg, args),
      debug: (msg, ...args) => {
        if (process.env.DEBUG) logJson("debug", msg, args);
      },
    };
  }

  const prefix = `[${component}]`;
  return {
    info: (msg, ...args) => console.log(prefix, msg, ...args),
    warn: (msg, ...args) => console.warn(prefix, msg, ...args),
    error: (msg, ...args) => console.error(prefix, msg, ...args),
    debug: (msg, ...args) => {
      if (process.env.DEBUG) console.debug(prefix, msg, ...args);
    },
  };
}
