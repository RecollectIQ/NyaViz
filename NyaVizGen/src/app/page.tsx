'use client';

import React, { useState, useRef, useCallback } from 'react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Separator } from '@/components/ui/separator';
import { AudioPlayer } from '@/components/AudioPlayer';
import { LyricsEditor } from '@/components/LyricsEditor';
import { TimingControls } from '@/components/TimingControls';
import { ExportPreview } from '@/components/ExportPreview';
import { 
  LyricLine,
  parseLyrics, 
  generateNyaVizContent,
} from '@/lib/types';

// SVG Icons
const Icons = {
  music: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M9 9l10.5-3m0 6.553v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 11-.99-3.467l2.31-.66a2.25 2.25 0 001.632-2.163zm0 0V2.25L9 5.25v10.303m0 0v3.75a2.25 2.25 0 01-1.632 2.163l-1.32.377a1.803 1.803 0 01-.99-3.467l2.31-.66A2.25 2.25 0 009 15.553z" />
    </svg>
  ),
  edit: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M16.862 4.487l1.687-1.688a1.875 1.875 0 112.652 2.652L10.582 16.07a4.5 4.5 0 01-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 011.13-1.897l8.932-8.931zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0115.75 21H5.25A2.25 2.25 0 013 18.75V8.25A2.25 2.25 0 015.25 6H10" />
    </svg>
  ),
  document: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
    </svg>
  ),
  download: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
    </svg>
  ),
  copy: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M15.666 3.888A2.25 2.25 0 0013.5 2.25h-3c-1.03 0-1.9.693-2.166 1.638m7.332 0c.055.194.084.4.084.612v0a.75.75 0 01-.75.75H9a.75.75 0 01-.75-.75v0c0-.212.03-.418.084-.612m7.332 0c.646.049 1.288.11 1.927.184 1.1.128 1.907 1.077 1.907 2.185V19.5a2.25 2.25 0 01-2.25 2.25H6.75A2.25 2.25 0 014.5 19.5V6.257c0-1.108.806-2.057 1.907-2.185a48.208 48.208 0 011.927-.184" />
    </svg>
  ),
  arrow: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M13.5 4.5L21 12m0 0l-7.5 7.5M21 12H3" />
    </svg>
  ),
  back: (
    <svg className="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M10.5 19.5L3 12m0 0l7.5-7.5M3 12h18" />
    </svg>
  ),
  clock: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" />
    </svg>
  ),
  palette: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M4.098 19.902a3.75 3.75 0 005.304 0l6.401-6.402M6.75 21A3.75 3.75 0 013 17.25V4.125C3 3.504 3.504 3 4.125 3h5.25c.621 0 1.125.504 1.125 1.125v4.072M6.75 21a3.75 3.75 0 003.75-3.75V8.197M6.75 21h13.125c.621 0 1.125-.504 1.125-1.125v-5.25c0-.621-.504-1.125-1.125-1.125h-4.072M10.5 8.197l2.88-2.88c.438-.439 1.15-.439 1.59 0l3.712 3.713c.44.44.44 1.152 0 1.59l-2.879 2.88M6.75 17.25h.008v.008H6.75v-.008z" />
    </svg>
  ),
  file: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M19.5 14.25v-2.625a3.375 3.375 0 00-3.375-3.375h-1.5A1.125 1.125 0 0113.5 7.125v-1.5a3.375 3.375 0 00-3.375-3.375H8.25m0 12.75h7.5m-7.5 3H12M10.5 2.25H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 00-9-9z" />
    </svg>
  ),
  headphones: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M19.114 5.636a9 9 0 010 12.728M16.463 8.288a5.25 5.25 0 010 7.424M6.75 8.25l4.72-4.72a.75.75 0 011.28.53v15.88a.75.75 0 01-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.01 9.01 0 012.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75z" />
    </svg>
  ),
  textEdit: (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24" strokeWidth={1.5}>
      <path strokeLinecap="round" strokeLinejoin="round" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12" />
    </svg>
  ),
};

type AppMode = 'input' | 'editor';

export default function Home() {
  const [mode, setMode] = useState<AppMode>('input');
  const [rawLyrics, setRawLyrics] = useState('');
  const [lines, setLines] = useState<LyricLine[]>([]);
  const [currentLineIndex, setCurrentLineIndex] = useState(0);
  const [isTimingMode, setIsTimingMode] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [showExportPreview, setShowExportPreview] = useState(false);
  
  const audioRef = useRef<HTMLAudioElement>(null);

  const handleParseLyrics = useCallback(() => {
    if (rawLyrics.trim()) {
      const parsed = parseLyrics(rawLyrics);
      setLines(parsed);
      setMode('editor');
    }
  }, [rawLyrics]);

  const handleBackToInput = useCallback(() => {
    setMode('input');
    setIsTimingMode(false);
    setCurrentLineIndex(0);
  }, []);

  const handleTimeUpdate = useCallback((time: number) => {
    setCurrentTime(time);
  }, []);

  const handleLoadedMetadata = useCallback((dur: number) => {
    setDuration(dur);
  }, []);

  const getCurrentTime = useCallback(() => {
    return audioRef.current ? audioRef.current.currentTime * 1000 : 0;
  }, []);

  const handlePlay = useCallback(() => {
    audioRef.current?.play();
  }, []);

  const isAudioLoaded = duration > 0;
  const isPlaying = audioRef.current ? !audioRef.current.paused : false;

  const handleDownload = useCallback(() => {
    const content = generateNyaVizContent(lines);
    const blob = new Blob([content], { type: 'text/plain' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'lyrics.nyaviz';
    document.body.appendChild(a);
    a.click();
    document.body.removeChild(a);
    URL.revokeObjectURL(url);
  }, [lines]);

  const timedLinesCount = lines.filter(l => l.startTime !== null && l.endTime !== null).length;

  return (
    <div className="min-h-screen bg-[var(--background)]">
      {/* Subtle gradient overlay */}
      <div className="fixed inset-0 pointer-events-none bg-gradient-to-b from-[var(--gray-900)]/50 via-transparent to-[var(--gray-950)]" />

      <div className="relative z-10">
        {/* Header */}
        <header className="border-b border-[var(--border)] bg-[var(--gray-900)]/80 backdrop-blur-xl sticky top-0 z-50">
          <div className="max-w-7xl mx-auto px-6 py-4">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-gradient-to-br from-[var(--gray-700)] to-[var(--gray-800)] flex items-center justify-center shadow-soft border border-[var(--gray-700)]">
                  {Icons.music}
                </div>
                <div>
                  <h1 className="text-xl font-semibold text-[var(--foreground)]">
                    NyaViz Generator
          </h1>
                  <p className="text-xs text-[var(--muted-foreground)]">Create lyric visualizations</p>
                </div>
              </div>

              {mode === 'editor' && (
                <div className="flex items-center gap-3">
                  <Button
                    variant="ghost"
                    onClick={handleBackToInput}
                    className="text-[var(--muted-foreground)] hover:text-[var(--foreground)] hover:bg-[var(--gray-800)]"
                  >
                    {Icons.back}
                    <span className="ml-2">Edit Lyrics</span>
                  </Button>
                  
                  <Button
                    onClick={() => setShowExportPreview(true)}
                    disabled={timedLinesCount === 0}
                    className="btn-primary text-[var(--foreground)] disabled:opacity-30"
                  >
                    {Icons.document}
                    <span className="ml-2">Export .nyaviz</span>
                  </Button>
                </div>
              )}
            </div>
          </div>
        </header>

        {/* Main Content */}
        <main className="max-w-7xl mx-auto px-6 py-8">
          {mode === 'input' ? (
            /* Input Mode */
            <div className="max-w-2xl mx-auto space-y-8">
              <div className="text-center space-y-3">
                <h2 className="text-3xl font-semibold text-[var(--foreground)]">
                  Enter Your Lyrics
                </h2>
                <p className="text-[var(--muted-foreground)]">
                  Paste your song lyrics below, one line per entry
          </p>
        </div>

              <Card className="bg-[var(--gray-900)] border-[var(--border)] shadow-soft">
                <CardContent className="pt-6">
                  <Textarea
                    value={rawLyrics}
                    onChange={(e) => setRawLyrics(e.target.value)}
                    placeholder={`Enter your lyrics here...

Example:
Welcome to the violet garden
How much you must have suffered through my anger
Through patches of violet we wander
Violet dreams and golden seams`}
                    className="h-[400px] max-h-[400px] bg-[var(--gray-850)] border-[var(--border)] text-[var(--foreground)] placeholder:text-[var(--muted-foreground)] resize-none font-mono inset-soft rounded-lg overflow-y-auto"
                  />
                </CardContent>
              </Card>

              <Button
                onClick={handleParseLyrics}
                disabled={!rawLyrics.trim()}
                size="lg"
                className="w-full h-14 text-lg btn-primary text-[var(--foreground)] disabled:opacity-30"
              >
                {Icons.arrow}
                <span className="ml-2">Continue to Editor</span>
              </Button>

              {/* Features Preview */}
              <div className="grid grid-cols-3 gap-4 pt-8">
                {[
                  { icon: Icons.clock, title: 'Sync Timing', desc: 'Press & hold to time each line' },
                  { icon: Icons.palette, title: 'Color Words', desc: 'Select and colorize lyrics' },
                  { icon: Icons.file, title: 'Export NyaViz', desc: 'Download ready-to-use files' },
                ].map((feature) => (
                  <div key={feature.title} className="p-4 rounded-xl bg-[var(--gray-900)] border border-[var(--border)] text-center shadow-soft">
                    <div className="mb-3 inline-flex p-2 rounded-lg bg-[var(--gray-800)]">
                      {feature.icon}
                    </div>
                    <div className="font-medium text-[var(--foreground)]">{feature.title}</div>
                    <div className="text-xs text-[var(--muted-foreground)] mt-1">{feature.desc}</div>
                  </div>
                ))}
              </div>
            </div>
          ) : (
            /* Editor Mode */
            <div className="grid grid-cols-1 lg:grid-cols-3 gap-6 h-[calc(100vh-180px)]">
              {/* Left Panel: Lyrics Editor */}
              <div className="lg:col-span-2 flex flex-col min-h-0">
                <Card className="flex-1 flex flex-col bg-[var(--gray-900)] border-[var(--border)] shadow-soft min-h-0">
                  <CardHeader className="flex-shrink-0 pb-3 border-b border-[var(--border)]">
                    <CardTitle className="flex items-center gap-2 text-[var(--foreground)]">
                      {Icons.textEdit}
                      <span>Lyrics</span>
                      <span className="ml-auto text-sm font-normal text-[var(--muted-foreground)]">
                        {lines.length} lines
                      </span>
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="flex-1 flex flex-col pt-0 min-h-0">
                    <LyricsEditor
                      lines={lines}
                      onUpdateLines={setLines}
                      currentLineIndex={currentLineIndex}
                      isTimingMode={isTimingMode}
                      currentTime={currentTime}
                    />
                  </CardContent>
                </Card>
              </div>

              {/* Right Panel: Controls */}
              <div className="space-y-6">
                {/* Audio Player */}
                <Card className="bg-[var(--gray-900)] border-[var(--border)] shadow-soft">
                  <CardHeader className="pb-3 border-b border-[var(--border)]">
                    <CardTitle className="flex items-center gap-2 text-[var(--foreground)]">
                      {Icons.headphones}
                      <span>Audio</span>
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="pt-4">
                    <AudioPlayer
                      onTimeUpdate={handleTimeUpdate}
                      onLoadedMetadata={handleLoadedMetadata}
                      isTimingMode={isTimingMode}
                      audioRef={audioRef}
                    />
                  </CardContent>
                </Card>

                <Separator className="bg-[var(--border)]" />

                {/* Timing Controls */}
                <Card className="bg-[var(--gray-900)] border-[var(--border)] shadow-soft">
                  <CardHeader className="pb-3 border-b border-[var(--border)]">
                    <CardTitle className="flex items-center gap-2 text-[var(--foreground)]">
                      {Icons.clock}
                      <span>Timing</span>
                    </CardTitle>
                  </CardHeader>
                  <CardContent className="pt-4">
                    <TimingControls
                      lines={lines}
                      onUpdateLines={setLines}
                      currentLineIndex={currentLineIndex}
                      onLineIndexChange={setCurrentLineIndex}
                      isTimingMode={isTimingMode}
                      onTimingModeChange={setIsTimingMode}
                      getCurrentTime={getCurrentTime}
                      isAudioLoaded={isAudioLoaded}
                      isPlaying={isPlaying}
                      onPlay={handlePlay}
                    />
                  </CardContent>
                </Card>

                {/* Quick Stats */}
                {timedLinesCount > 0 && (
                  <div className="p-4 rounded-xl bg-[var(--gray-850)] border border-[var(--border)] shadow-soft">
                    <div className="text-xs text-[var(--muted-foreground)] mb-1">Ready to export</div>
                    <div className="text-2xl font-semibold text-[var(--foreground)]">
                      {timedLinesCount} lines
                    </div>
                    <div className="text-xs text-[var(--muted-foreground)]">
                      with timing data
                    </div>
                  </div>
                )}
              </div>
        </div>
          )}
      </main>
      </div>

      {/* Export Preview Modal */}
      {showExportPreview && (
        <ExportPreview
          lines={lines}
          onUpdateLines={setLines}
          onExport={handleDownload}
          onClose={() => setShowExportPreview(false)}
          audioRef={audioRef}
          duration={duration}
        />
      )}
    </div>
  );
}
