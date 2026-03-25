import { z } from "zod";
import { defineTool, mcpSuccess } from "./tool-utils.js";
import { AVAILABLE_ENVIRONMENTS } from "./environment-constants.js";

export const getAvailableEnvironmentsTool = defineTool({
  name: "get_available_environments",
  description:
    "사용 가능한 에이전트 실행 환경(컨테이너 이미지) 목록을 조회합니다. " +
    "다음 사이클에서 다른 환경이 필요한 경우, 이 목록을 확인한 후 " +
    "set_export_config의 next_environment 필드에 환경 ID를 지정할 수 있습니다.",
  schema: z.object({}),
  handler: () => {
    return mcpSuccess({ success: true, environments: AVAILABLE_ENVIRONMENTS });
  },
});
