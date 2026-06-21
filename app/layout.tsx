import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Legacy - Europe Monitor",
  description: "Legacy Capital Europe activity, inflation and ECB communication monitor.",
  icons: {
    icon: "/favicon.svg",
    shortcut: "/favicon.svg",
  },
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
