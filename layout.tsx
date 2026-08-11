import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Control Horarios",
  description: "Registro, control y auditoria profesional del tiempo de trabajo.",
  icons: { icon: "/favicon.svg", shortcut: "/favicon.svg" },
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="es"><body>{children}</body></html>;
}
