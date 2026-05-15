export type TerminalPoint = {
  x: number;
  y: number;
};

export type SelectionRange = {
  start: TerminalPoint;
  end: TerminalPoint;
};

export type RasterFrame = {
  width: number;
  height: number;
  pixels: number[][][] | Uint8ClampedArray | Uint8Array | number[];
};

export type BrowserAdapterOptions = {
  url?: string;
  socket?: WebSocket;
  sessionId?: string;
  clientId?: string;
  cols?: number;
  rows?: number;
  binary?: boolean;
  canvas?: HTMLCanvasElement;
  renderer?: "screen" | "raster" | "webgl" | string;
  renderers?: string[];
  raster?: boolean;
  terminalOptions?: Record<string, unknown>;
};

export type BrowserAdapterMessage = {
  type: string;
  session_id?: string;
  sessionId?: string;
  payload?: Record<string, unknown>;
};

export type BrowserAdapterCommand = {
  type: string;
  payload?: Record<string, unknown>;
};

export class RTermWebGLRenderer {
  constructor(canvas: HTMLCanvasElement, options?: Record<string, unknown>);
  render(frame: RasterFrame): void;
  resize(width: number, height: number): void;
  dispose(): void;
}

export class RTermBrowserAdapter extends EventTarget {
  constructor(target: string | Element, options?: BrowserAdapterOptions);

  element: Element;
  sessionId: string | null;
  clientId: string;
  cols: number;
  rows: number;
  cell: { width: number; height: number };
  canvas: HTMLCanvasElement | null;

  connect(urlOrSocket: string | WebSocket): this;
  send(type: string, payload?: Record<string, unknown>, sessionId?: string | null): BrowserAdapterMessage;
  sendHostEvent(payload: Record<string, unknown>): BrowserAdapterMessage;
  createSessionPayload(): Record<string, unknown>;
  decodeMessage(data: string | Blob | ArrayBuffer): void;
  handleMessage(message: BrowserAdapterMessage): void;
  handleBinary(bytes: Uint8Array): void;
  applySnapshot(payload: Record<string, unknown>): void;
  applyCommand(command: BrowserAdapterCommand): void;
  renderScreen(screen: Record<string, unknown>): void;
  renderRaster(frame: RasterFrame): void;
  fit(): { cols: number; rows: number; cell: { width: number; height: number } };
  refresh(): this;
  focus(): this;
  blur(): this;
  setOption(name: string, value: unknown): this;
  getOption(name: string): unknown;
  resizeToElement(): void;
  dispose(): void;
}

export default RTermBrowserAdapter;
