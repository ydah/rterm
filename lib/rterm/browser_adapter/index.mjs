import "./webgl_renderer.js";
import "./browser_adapter.js";

const root = typeof window !== "undefined" ? window : globalThis;

export const RTermWebGLRenderer = root.RTermWebGLRenderer;
export const RTermBrowserAdapter = root.RTermBrowserAdapter;

export default RTermBrowserAdapter;
