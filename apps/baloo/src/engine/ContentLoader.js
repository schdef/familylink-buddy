/* src/engine/ContentLoader.js */
import augeTopic from '../../content/topics/das-auge/topic.json';
import { getLectures, getLecture as getStoreLecture, saveLecture } from './LectureStore';

// Simple in-memory list of built-in topics
const builtInTopics = [augeTopic];

export function getTopicsList() {
  // Get built-in
  const list = [...builtInTopics];
  
  // Get custom lectures from LectureStore
  try {
    const customLectures = getLectures();
    customLectures.forEach(l => {
      list.push({
        id: l.id,
        title: l.title,
        description: l.description,
        icon: l.icon || '📖',
        ageRange: l.ageRange || [6, 12],
        difficulty: l.difficulty || 'Mittel',
        isCustom: true,
        category: l.category || 'Allgemein',
        cards: l.cards || [],
        puzzlePieces: l.puzzlePieces || []
      });
    });
  } catch (e) {
    console.error('Error loading custom lectures list:', e);
  }
  
  return list;
}

export function getTopicById(id) {
  // Check built-in first
  const builtIn = builtInTopics.find(t => t.id === id);
  if (builtIn) return builtIn;
  
  // Check custom lectures in LectureStore
  try {
    const custom = getStoreLecture(id);
    if (custom) return custom;
  } catch (e) {
    console.error('Error loading custom lecture:', e);
  }
  
  return null;
}

export function saveCustomLecture(lecture) {
  try {
    saveLecture(lecture);
    return true;
  } catch (e) {
    console.error('Error saving custom lecture:', e);
    return false;
  }
}

