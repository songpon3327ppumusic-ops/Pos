import type { Config } from "tailwindcss";
const config: Config = {
  content: ["./app/**/*.{js,ts,jsx,tsx}", "./components/**/*.{js,ts,jsx,tsx}"],
  theme: { extend: { colors: { ink: "#172B4D", mint: "#E8F7F1", brand: "#14966B" }, boxShadow: { soft: "0 8px 30px rgba(24, 45, 72, .06)" } } },
  plugins: []
};
export default config;