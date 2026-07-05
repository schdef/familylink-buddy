/* src/games/QuizGame.jsx */
import { useState, useEffect } from 'preact/hooks';
import { shuffle } from '../utils/shuffle';
import { addStars } from '../engine/StarEconomy';
import { getLanguage, t } from '../utils/i18n';
import { ProgressBar } from '../components/ProgressBar';
import { FeedbackBanner } from '../components/FeedbackBanner';
import { ResultBox } from '../components/ResultBox';
import { stripSvgLabels } from '../utils/svgUtils';

export function QuizGame({ cards, onComplete }) {
  const lang = getLanguage();
  const [questions, setQuestions] = useState([]);
  const [currentIdx, setCurrentIdx] = useState(0);
  const [score, setScore] = useState(0);
  const [starsEarned, setStarsEarned] = useState(0);
  const [selectedOpt, setSelectedOpt] = useState(null);
  const [correctOpt, setCorrectOpt] = useState(null);
  const [options, setOptions] = useState([]);
  const [firstAttempt, setFirstAttempt] = useState(true);
  const [isDone, setIsDone] = useState(false);
  const [feedback, setFeedback] = useState({ status: null, message: '' });

  // Call onComplete when done
  useEffect(() => {
    if (isDone && onComplete) {
      onComplete();
    }
  }, [isDone]);

  const getTranslated = (obj, field) => {
    if (!obj || !obj[field]) return '';
    return obj[field][lang] || obj[field].de || '';
  };

  // Initialize Quiz questions
  useEffect(() => {
    if (cards.length > 0) {
      setQuestions(shuffle(cards));
      setCurrentIdx(0);
      setScore(0);
      setStarsEarned(0);
      setIsDone(false);
      setSelectedOpt(null);
      setFeedback({ status: null, message: '' });
    }
  }, [cards]);

  // Set up options for current question
  useEffect(() => {
    if (questions.length > 0 && currentIdx < questions.length) {
      const correctCard = questions[currentIdx];
      const correctName = getTranslated(correctCard, 'term');
      setCorrectOpt(correctName);

      // Gather distractors
      const otherCards = cards.filter(c => getTranslated(c, 'term') !== correctName);
      const distractors = shuffle(otherCards).slice(0, 3);
      
      // Merge correct option and distractors, then shuffle
      const quizOptions = shuffle([correctCard, ...distractors]);
      setOptions(quizOptions);
      
      // Reset state for new question
      setSelectedOpt(null);
      setFeedback({ status: null, message: '' });
      setFirstAttempt(true);
    }
  }, [questions, currentIdx]);

  const handleSelectOption = (termText, btnEl) => {
    if (selectedOpt) return; // Answer already submitted

    setSelectedOpt(termText);
    const isCorrect = termText === correctOpt;

    if (isCorrect) {
      setFeedback({
        status: 'correct',
        message: t('game.feedback.correct')
      });
      
      if (firstAttempt) {
        setScore(prev => prev + 1);
        setStarsEarned(prev => prev + 1);
        addStars(1);
      }
    } else {
      setFeedback({
        status: 'wrong',
        message: t('game.feedback.wrong', { correct: correctOpt })
      });
      setFirstAttempt(false);
    }
  };

  const handleNext = () => {
    if (currentIdx + 1 >= questions.length) {
      setIsDone(true);
    } else {
      setCurrentIdx(prev => prev + 1);
    }
  };

  if (questions.length === 0) return null;

  if (isDone) {
    return (
      <ResultBox 
        correct={score} 
        total={questions.length} 
        starsEarned={starsEarned}
        onRetry={() => {
          setQuestions(shuffle(cards));
          setCurrentIdx(0);
          setScore(0);
          setStarsEarned(0);
          setIsDone(false);
          setSelectedOpt(null);
          setFeedback({ status: null, message: '' });
        }}
      />
    );
  }

  const currentCard = questions[currentIdx];

  return (
    <div class="quiz-wrap">
      
      {/* Quiz Progress & Score header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: '0.85rem', color: 'var(--color-text-secondary)' }}>
        <span>⭐ {starsEarned} {t('app.stars_count')}</span>
        <span>{t('game.score', { correct: score, total: currentIdx + 1 })}</span>
      </div>

      <ProgressBar current={currentIdx} total={questions.length} />

      {/* SVG Image Box - text labels stripped to avoid showing the answer */}
      <div class="q-svg-box">
        <div 
          dangerouslySetInnerHTML={{ __html: stripSvgLabels(currentCard.svg) }} 
          style={{ width: '100%', height: '100%' }}
        />
      </div>

      <h2 class="q-text">
        {t('quiz.question_prompt')}
      </h2>

      {/* Quiz Options Grid */}
      <div class="q-opts">
        {options.map((opt, idx) => {
          const optName = getTranslated(opt, 'term');
          const isSelected = selectedOpt === optName;
          const isCorrect = optName === correctOpt;
          
          let optClass = 'q-opt';
          if (selectedOpt) {
            if (isCorrect) optClass += ' correct';
            else if (isSelected) optClass += ' wrong';
          }

          return (
            <button
              key={idx}
              type="button"
              class={optClass}
              disabled={!!selectedOpt}
              onClick={(e) => handleSelectOption(optName, e.currentTarget)}
            >
              {optName}
            </button>
          );
        })}
      </div>

      {/* Feedback Banner */}
      <FeedbackBanner status={feedback.status} message={feedback.message} />

      {/* Next button */}
      {selectedOpt && (
        <button 
          type="button" 
          class="btn btn-primary btn-full" 
          onClick={handleNext}
          style={{ marginTop: '0.5rem' }}
        >
          {t('game.next')}
        </button>
      )}

    </div>
  );
}
