import { en } from "./locales/en";
import { es } from "./locales/es";
import { pl } from "./locales/pl";

export const supportedLanguages = ["es", "pl", "en"] as const;
export type SupportedLanguage = (typeof supportedLanguages)[number];
const dictionaries = { es, pl, en } as const;

export function isSupportedLanguage(value: string | undefined): value is SupportedLanguage {
  return supportedLanguages.includes(value as SupportedLanguage);
}

export function getDictionary(language: SupportedLanguage) {
  return dictionaries[language];
}
