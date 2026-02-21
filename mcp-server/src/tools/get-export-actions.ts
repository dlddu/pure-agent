import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";
import { EXPORT_ACTIONS } from "./export-constants.js";

export const getExportActionsTool = defineTool({
  name: "get_export_actions",
  description:
    "사용 가능한 export action 목록을 조회합니다. 작업 완료 후 결과물을 내보내는 방법을 확인할 때 사용합니다.",
  schema: z.object({}),
  handler: () => {
    return mcpSuccess({ success: true, actions: EXPORT_ACTIONS });
  },
});
