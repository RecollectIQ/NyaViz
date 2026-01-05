// Types for NyaViz Generator

export interface LyricLine {
  id: string;
  text: string;
  words: Word[];
  startTime: number | null; // in milliseconds
  endTime: number | null;
  secondaryText?: string; // for translations/echoes
  markedForReview?: boolean; // flag for potential timing errors
}

export interface Word {
  id: string;
  text: string;
  color: string | null; // hex color or null for default
  isBold: boolean;
  isItalic: boolean;
}

export interface TimingSession {
  isActive: boolean;
  currentLineIndex: number;
  pressStartTime: number | null;
}

export interface ColorPreset {
  name: string;
  hex: string;
}

export const DEFAULT_COLOR_PRESETS: ColorPreset[] = [
  { name: 'red', hex: '#ef4444' },
  { name: 'orange', hex: '#f97316' },
  { name: 'gold', hex: '#fbbf24' },
  { name: 'yellow', hex: '#facc15' },
  { name: 'lime', hex: '#84cc16' },
  { name: 'green', hex: '#22c55e' },
  { name: 'teal', hex: '#14b8a6' },
  { name: 'cyan', hex: '#06b6d4' },
  { name: 'blue', hex: '#3b82f6' },
  { name: 'indigo', hex: '#6366f1' },
  { name: 'violet', hex: '#8b5cf6' },
  { name: 'purple', hex: '#a855f7' },
  { name: 'fuchsia', hex: '#d946ef' },
  { name: 'pink', hex: '#ec4899' },
  { name: 'crimson', hex: '#dc143c' },
  { name: 'white', hex: '#ffffff' },
];

// Generate unique ID
export function generateId(): string {
  return Math.random().toString(36).substring(2, 11);
}

// Parse lyrics text into lines
export function parseLyrics(text: string): LyricLine[] {
  const lines = text.split('\n').filter(line => line.trim().length > 0);
  return lines.map(line => ({
    id: generateId(),
    text: line.trim(),
    words: parseWordsFromLine(line.trim()),
    startTime: null,
    endTime: null,
  }));
}

// Parse a line into individual words, separating leading/trailing punctuation
// Apostrophes adjacent to word characters stay with the word (e.g., "can't", "askin'", "'cause")
export function parseWordsFromLine(line: string): Word[] {
  const tokens = line.split(/(\s+)/).filter(w => w.length > 0);
  const result: Word[] = [];
  
  for (const token of tokens) {
    // If it's whitespace, add as-is
    if (/^\s+$/.test(token)) {
      result.push({
        id: generateId(),
        text: token,
        color: null,
        isBold: false,
        isItalic: false,
      });
      continue;
    }
    
    // Extract leading punctuation
    // Stop if we hit a word char, or an apostrophe followed by a word char
    let i = 0;
    while (i < token.length) {
      const char = token[i];
      const nextChar = token[i + 1];
      
      if (/\w/.test(char)) break;
      if (char === "'" && nextChar && /\w/.test(nextChar)) break;
      
      i++;
    }
    const leadingPunct = token.slice(0, i);
    
    // Extract trailing punctuation
    // Stop if we hit a word char, or an apostrophe preceded by a word char
    let j = token.length - 1;
    while (j >= i) {
      const char = token[j];
      const prevChar = token[j - 1];
      
      if (/\w/.test(char)) break;
      if (char === "'" && prevChar && /\w/.test(prevChar)) break;
      
      j--;
    }
    const trailingPunct = token.slice(j + 1);
    const wordContent = token.slice(i, j + 1);
    
    // Add leading punctuation as separate token
    if (leadingPunct) {
      result.push({
        id: generateId(),
        text: leadingPunct,
        color: null,
        isBold: false,
        isItalic: false,
      });
    }
    
    // Add the word content (includes apostrophes adjacent to letters)
    if (wordContent) {
      result.push({
        id: generateId(),
        text: wordContent,
        color: null,
        isBold: false,
        isItalic: false,
      });
    }
    
    // Add trailing punctuation as separate token
    if (trailingPunct) {
      result.push({
        id: generateId(),
        text: trailingPunct,
        color: null,
        isBold: false,
        isItalic: false,
      });
    }
  }
  
  return result;
}

// Format time as HH:MM:SS,mmm
export function formatTime(ms: number): string {
  // Round to integer milliseconds
  const totalMs = Math.round(ms);
  const hours = Math.floor(totalMs / 3600000);
  const minutes = Math.floor((totalMs % 3600000) / 60000);
  const seconds = Math.floor((totalMs % 60000) / 1000);
  const milliseconds = totalMs % 1000;
  
  return `${hours.toString().padStart(2, '0')}:${minutes.toString().padStart(2, '0')}:${seconds.toString().padStart(2, '0')},${milliseconds.toString().padStart(3, '0')}`;
}

// Format time for display (MM:SS)
export function formatTimeDisplay(ms: number): string {
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

// Generate NyaViz file content
export function generateNyaVizContent(lines: LyricLine[]): string {
  const timedLines = lines.filter(line => line.startTime !== null && line.endTime !== null);
  
  let output = '';
  let sequenceNumber = 1;
  
  for (const line of timedLines) {
    output += `${sequenceNumber}\n`;
    output += `${formatTime(line.startTime!)} --> ${formatTime(line.endTime!)}\n`;
    output += formatLineWithStyles(line) + '\n\n';
    
    // Add secondary line if present
    if (line.secondaryText) {
      output += `${formatTime(line.startTime!)} --> ${formatTime(line.endTime!)}\n`;
      output += `(${line.secondaryText})\n\n`;
    }
    
    sequenceNumber++;
  }
  
  return output.trim();
}

// Format a line with color/style markers
function formatLineWithStyles(line: LyricLine): string {
  let result = '';
  
  for (const word of line.words) {
    let styledWord = word.text;
    
    // Build style tags
    const styles: string[] = [];
    if (word.color) styles.push(word.color);
    if (word.isBold) styles.push('b');
    if (word.isItalic) styles.push('i');
    
    if (styles.length > 0) {
      const styleStr = styles.join(' ');
      styledWord = `[${styleStr}]${word.text}[/]`;
    }
    
    result += styledWord;
  }
  
  return result;
}

