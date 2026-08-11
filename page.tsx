import { getDictionary, isSupportedLanguage } from "@/i18n";
import Link from "next/link";

type HomeProps = { searchParams?: Promise<{ lang?: string }> };

export default async function Home({ searchParams }: HomeProps) {
  const params = await searchParams;
  const language = isSupportedLanguage(params?.lang) ? params.lang : "es";
  const t = getDictionary(language);

  return (
    <main>
      <section className="foundation-card" aria-labelledby="page-title">
        <div className="brand-mark" aria-hidden="true">CH</div>
        <p className="eyebrow">{t.foundation.phase}</p>
        <h1 id="page-title">{t.app.name}</h1>
        <p className="lede">{t.foundation.summary}</p>
        <dl className="status-grid">
          <div><dt>{t.foundation.database}</dt><dd>{t.foundation.ready}</dd></div>
          <div><dt>{t.foundation.security}</dt><dd>{t.foundation.ready}</dd></div>
          <div><dt>{t.foundation.languages}</dt><dd>ES · PL · EN</dd></div>
          <div><dt>{t.foundation.next}</dt><dd>{t.foundation.schedules}</dd></div>
        </dl>
        <nav aria-label={t.language.label} className="language-switcher">
          <Link href="/?lang=es" aria-current={language === "es" ? "page" : undefined}>ES</Link>
          <Link href="/?lang=pl" aria-current={language === "pl" ? "page" : undefined}>PL</Link>
          <Link href="/?lang=en" aria-current={language === "en" ? "page" : undefined}>EN</Link>
        </nav>
      </section>
    </main>
  );
}
