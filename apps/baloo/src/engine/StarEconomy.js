/* src/engine/StarEconomy.js */
import { sendRewardToFamilyLink } from './familyLinkSync';

// Default values
let starBalance = parseInt(localStorage.getItem('baloo_stars') || '0', 10);
let starsEarned = parseInt(localStorage.getItem('baloo_stars_earned') || '0', 10);
let starsSpent = parseInt(localStorage.getItem('baloo_stars_spent') || '0', 10);

export function getStarBalance() {
  return starBalance;
}

export function getStarsEarned() {
  return starsEarned;
}

export function getStarsSpent() {
  return starsSpent;
}

export function addStars(amount = 1) {
  if (amount <= 0) return;
  starBalance += amount;
  starsEarned += amount;
  
  localStorage.setItem('baloo_stars', starBalance.toString());
  localStorage.setItem('baloo_stars_earned', starsEarned.toString());
  
  // Dispatch custom event to notify components
  window.dispatchEvent(new CustomEvent('starchange', { detail: { balance: starBalance } }));

  // FamilyLink Buddy Reward Integration
  const flEnabled = localStorage.getItem('baloo_familylink_enabled') === 'true';
  const flToken = localStorage.getItem('baloo_familylink_token');
  if (flEnabled && flToken) {
    const flMode = localStorage.getItem('baloo_familylink_mode') || 'emulator';
    const flRate = parseInt(localStorage.getItem('baloo_familylink_rate') || '2', 10);
    const minutesToReward = amount * flRate;
    
    sendRewardToFamilyLink(flToken, flMode, minutesToReward)
      .then((newRemaining) => {
        console.log(`Successfully rewarded ${minutesToReward} min screen time. New balance: ${newRemaining} min.`);
      })
      .catch((err) => {
        console.error(`Failed to send screen time reward to FamilyLink Buddy:`, err);
      });
  }
}

export function spendStars(amount = 10) {
  if (amount <= 0 || starBalance < amount) return false;
  
  starBalance -= amount;
  starsSpent += amount;
  
  localStorage.setItem('baloo_stars', starBalance.toString());
  localStorage.setItem('baloo_stars_spent', starsSpent.toString());
  
  // Dispatch custom event to notify components
  window.dispatchEvent(new CustomEvent('starchange', { detail: { balance: starBalance } }));
  return true;
}
