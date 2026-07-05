/* src/utils/i18n.js */
import deTranslations from '../../content/i18n/de.json';
import enTranslations from '../../content/i18n/en.json';

const translations = {
  de: deTranslations,
  en: enTranslations
};

let currentLang = localStorage.getItem('baloo_lang') || 
  (navigator.language.startsWith('en') ? 'en' : 'de');

// Set language helper
export function setLanguage(lang) {
  if (translations[lang]) {
    currentLang = lang;
    localStorage.setItem('baloo_lang', lang);
    // Dispatch event to trigger UI redraws
    window.dispatchEvent(new Event('languagechange'));
  }
}

// Get current language
export function getLanguage() {
  return currentLang;
}

// Translate utility
export function t(key, params = {}) {
  const dictionary = translations[currentLang] || translations.de;
  let text = dictionary[key] || translations.de[key] || key;
  
  // Format variables like {count}
  Object.keys(params).forEach(paramKey => {
    text = text.replace(new RegExp(`{${paramKey}}`, 'g'), params[paramKey]);
  });
  
  return text;
}
