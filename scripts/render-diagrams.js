// Renders every ```plantuml block in docs/*.md to docs/diagrams/<name>.svg and embeds the
// image in the markdown, keeping the source in a <details> block.
//
//   node scripts/render-diagrams.js            # render + embed
//   node scripts/render-diagrams.js --check    # fail if any SVG is missing/stale
//
// Why pre-render: GitHub does not render PlantUML at all, and Markdown Preview Enhanced needs
// a local plantuml.jar. A committed SVG renders everywhere — VSCode, GitHub, Word, PDF export.
//
// Uses kroki.io over HTTPS; no local Java or jar required. Set KROKI_URL to self-host.

const fs = require("fs");
const path = require("path");
const https = require("https");

const KROKI = process.env.KROKI_URL || "https://kroki.io/plantuml/svg";
const DOCS = "docs";
const OUT = path.join(DOCS, "diagrams");
const CHECK = process.argv.includes("--check");

// Friendly alt text / caption per diagram.
const TITLES = {
  "actor-hierarchy": "Sơ đồ kế thừa actor",
  "package-overview": "Tổng quan các gói chức năng",
  "p1-account": "P1 — Quản lý tài khoản & cá nhân hoá",
  "p2-discovery": "P2 — Khám phá & Lộ trình học",
  "p3-learning": "P3 — Học tập",
  "p4-practice": "P4 — Luyện tập & Chấm bài",
  "p5-authoring": "P5 — Soạn & Quản lý nội dung",
  "p6-groups": "P6 — Nhóm học tập",
  "p7-ai": "P7 — Trợ lý AI",
  "p8-admin": "P8 — Quản trị hệ thống",
  "p9-scheduled": "P9 — Tác vụ tự động",
};

function render(source) {
  return new Promise((resolve, reject) => {
    const req = https.request(
      KROKI,
      { method: "POST", headers: { "Content-Type": "text/plain" }, timeout: 30000 },
      (res) => {
        const chunks = [];
        res.on("data", (c) => chunks.push(c));
        res.on("end", () => {
          const body = Buffer.concat(chunks);
          if (res.statusCode !== 200) {
            return reject(new Error(`kroki ${res.statusCode}: ${body.toString().slice(0, 300)}`));
          }
          resolve(body);
        });
      },
    );
    req.on("timeout", () => req.destroy(new Error("kroki timeout")));
    req.on("error", reject);
    req.end(source);
  });
}

const FENCE = /```plantuml\r?\n([\s\S]*?)```/g;

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  let rendered = 0;
  let wrapped = 0;
  const stale = [];

  for (const file of fs.readdirSync(DOCS).filter((f) => f.endsWith(".md"))) {
    const full = path.join(DOCS, file);
    let md = fs.readFileSync(full, "utf8");
    const blocks = [...md.matchAll(FENCE)];
    if (!blocks.length) continue;

    // Process back-to-front so earlier offsets stay valid while splicing.
    for (const m of blocks.reverse()) {
      const source = m[1].trimEnd();
      const name = (source.match(/@startuml\s+([A-Za-z0-9_-]+)/) || [])[1];
      if (!name) {
        throw new Error(`${file}: a plantuml block has no name — use "@startuml <name>"`);
      }

      const svgPath = path.join(OUT, `${name}.svg`);
      const title = TITLES[name] || name;

      if (CHECK) {
        if (!fs.existsSync(svgPath)) stale.push(`${name}.svg thiếu`);
        continue;
      }

      const svg = await render(source);
      fs.writeFileSync(svgPath, svg);
      rendered += 1;

      // Already wrapped? Then only the SVG needed refreshing.
      const before = md.slice(0, m.index);
      if (before.trimEnd().endsWith(`<!-- diagram:${name} -->`) || before.includes(`<!-- diagram:${name} -->`)) {
        continue;
      }

      const replacement =
        `<!-- diagram:${name} -->\n` +
        `![${title}](diagrams/${name}.svg)\n\n` +
        `<details><summary>Mã nguồn PlantUML — sửa ở đây rồi chạy <code>node scripts/render-diagrams.js</code></summary>\n\n` +
        "```plantuml\n" +
        source +
        "\n```\n\n" +
        `</details>\n` +
        `<!-- /diagram:${name} -->`;

      md = md.slice(0, m.index) + replacement + md.slice(m.index + m[0].length);
      wrapped += 1;
    }

    fs.writeFileSync(full, md);
  }

  if (CHECK) {
    if (stale.length) {
      console.error("Sơ đồ chưa được render:\n  " + stale.join("\n  "));
      process.exit(1);
    }
    console.log("✓ mọi sơ đồ đều đã có SVG");
    return;
  }

  console.log(`✓ render ${rendered} sơ đồ → ${OUT}/  (nhúng mới: ${wrapped})`);
})().catch((e) => {
  console.error("Lỗi:", e.message);
  process.exit(1);
});
