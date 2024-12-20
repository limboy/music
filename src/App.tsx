import { useState, useEffect, useRef } from 'react'
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTrigger } from "@/components/ui/dialog"
import { Drawer, DrawerContent, DrawerDescription, DrawerHeader, DrawerTitle, DrawerTrigger } from "@/components/ui/drawer"
import { useMediaQuery } from "@/hooks/use-media-query"
import './App.css'
import { DialogTitle } from '@radix-ui/react-dialog'
import { PlayIcon, PauseIcon, ListIcon, ChevronLeftIcon, ChevronRightIcon } from "lucide-react"
import { Button } from "@/components/ui/button"

interface Song {
  id: string;
  name: string;
  singer: string;
  album: string;
  cover: string;
  song: string;
  duration: string;
}

interface ApiResponse {
  items: Song[];
}

function PlaylistContent({ songs, currentSong, onSelect }: {
  songs: Song[],
  currentSong: Song | null,
  onSelect: (song: Song) => void
}) {
  return (
    <div className="playlist">
      {songs.map((song) => (
        <div
          key={song.id}
          className={`playlist-item ${currentSong?.id === song.id ? 'active' : ''}`}
          onClick={() => onSelect(song)}
        >
          <img
            src={`https://pb.limboy.me/api/files/music/${song.id}/${song.cover}`}
            alt={song.name}
            className="playlist-cover"
          />
          <div className="playlist-info">
            <div className="song-name">{song.name}</div>
            <div className="singer-name">{song.singer}</div>
          </div>
        </div>
      ))}
    </div>
  )
}

function App() {
  const [songs, setSongs] = useState<Song[]>([]);
  const [currentSong, setCurrentSong] = useState<Song | null>(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [open, setOpen] = useState(false);
  const audioRef = useRef<HTMLAudioElement>(null);
  const isDesktop = useMediaQuery("(min-width: 768px)");

  useEffect(() => {
    fetch('https://pb.limboy.me/api/collections/music/records?sort=@random&perPage=300')
      .then(res => res.json())
      .then((data: ApiResponse) => {
        setSongs(data.items);
        setCurrentSong(data.items[0]);
      });
  }, []);

  useEffect(() => {
    if (currentSong && audioRef.current) {
      audioRef.current.src = `https://pb.limboy.me/api/files/music/${currentSong.id}/${currentSong.song}`;
      if (isPlaying) audioRef.current.play();
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [currentSong]);

  useEffect(() => {
    const handleTimeUpdate = () => setCurrentTime(audioRef.current?.currentTime || 0);
    const handleDurationChange = () => setDuration(audioRef.current?.duration || 0);

    const audioElement = audioRef.current;
    audioElement?.addEventListener('timeupdate', handleTimeUpdate);
    audioElement?.addEventListener('loadedmetadata', handleDurationChange);

    return () => {
      audioElement?.removeEventListener('timeupdate', handleTimeUpdate);
      audioElement?.removeEventListener('loadedmetadata', handleDurationChange);
    };
  }, []);

  useEffect(() => {
    if (currentSong) {
      document.title = `${currentSong.name} - ${currentSong.singer}`;
    }
  }, [currentSong]);

  const togglePlay = () => {
    if (!audioRef.current) return;

    if (isPlaying) {
      audioRef.current.pause();
    } else {
      audioRef.current.play();
    }
    setIsPlaying(!isPlaying);
  };

  const playNext = () => {
    const currentIndex = songs.findIndex(song => song.id === currentSong?.id);
    const nextSong = songs[(currentIndex + 1) % songs.length];
    setCurrentSong(nextSong);
    setIsPlaying(true);
  };

  const playPrev = () => {
    const currentIndex = songs.findIndex(song => song.id === currentSong?.id);
    const prevSong = songs[(currentIndex - 1 + songs.length) % songs.length];
    setCurrentSong(prevSong);
    setIsPlaying(true);
  };

  const handleProgressClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!audioRef.current) return;

    const rect = e.currentTarget.getBoundingClientRect();
    const ratio = (e.clientX - rect.left) / rect.width;
    audioRef.current.currentTime = ratio * duration;
  };

  const formatTime = (time: number | undefined) => {
    if (typeof time === 'undefined' || isNaN(time)) return '--:--';
    const minutes = Math.floor(time / 60);
    const seconds = Math.floor(time % 60);
    return `${minutes}:${seconds.toString().padStart(2, '0')}`;
  };

  const handleSongSelect = (song: Song) => {
    setCurrentSong(song);
    setIsPlaying(true);
    setOpen(false);
    setDuration(0); // Reset duration when changing songs
  };

  const handleSongEnd = () => {
    const currentIndex = songs.findIndex(song => song.id === currentSong?.id);
    const nextSong = songs[(currentIndex + 1) % songs.length];
    setCurrentSong(nextSong);
  };

  return (
    <div className="player">
      {currentSong && (
        <>
          <img
            src={`https://pb.limboy.me/api/files/music/${currentSong.id}/${currentSong.cover}`}
            alt={currentSong.name}
            className="cover"
          />
          <div className="info">
            <h2>{currentSong.name}</h2>
            <p>{currentSong.singer}</p>
          </div>
          <div className="progress-container">
            <div className="time">{formatTime(currentTime)}</div>
            <div className="progress-bar" onClick={handleProgressClick}>
              <div
                className="progress-fill"
                style={{ width: `${(currentTime / duration) * 100}%`, minWidth: '8px' }}
              />
            </div>
            <div className="time">{formatTime(duration || undefined)}</div>
          </div>
          <div className="controls">
            <Button
              variant="ghost"
              className="w-12 h-12 !rounded-full"
              size="icon"
              onClick={playPrev}
            >
              <ChevronLeftIcon className="!h-6 !w-6" />
            </Button>
            <Button
              variant="default"
              className="w-16 h-16 !rounded-full mx-4"
              size="icon"
              onClick={togglePlay}
            >
              {isPlaying ? (
                <PauseIcon className="!h-6 !w-6" />
              ) : (
                <PlayIcon className="!h-6 !w-6" />
              )}
            </Button>
            <Button
              variant="ghost"
              className="w-12 h-12 !rounded-full"
              size="icon"
              onClick={playNext}
            >
              <ChevronRightIcon className="!h-6 !w-6" />
            </Button>
          </div>
          <div className="playlist-control">
            {isDesktop ? (
              <Dialog open={open} onOpenChange={setOpen}>
                <DialogTrigger asChild>
                  <Button variant="outline">
                    <ListIcon className="h-4 w-4 mr-2" />
                    Playlist
                  </Button>
                </DialogTrigger>
                <DialogContent className="playlist-dialog">
                  <DialogHeader>
                    <DialogTitle className='-mt-2'>
                      <span className='text-gray-400 font-semibold inline-block'>Playlist</span>
                    </DialogTitle>
                    <DialogDescription></DialogDescription>
                  </DialogHeader>
                  <PlaylistContent
                    songs={songs}
                    currentSong={currentSong}
                    onSelect={handleSongSelect}
                  />
                </DialogContent>
              </Dialog>
            ) : (
              <Drawer open={open} onOpenChange={setOpen}>
                <DrawerTrigger asChild>
                  <Button variant="outline" className="playlist-btn">
                    <ListIcon className="h-4 w-4 mr-2" />
                    Playlist
                  </Button>
                </DrawerTrigger>
                <DrawerContent>
                  <DrawerHeader>
                    <DrawerTitle>Playlist</DrawerTitle>
                    <DrawerDescription></DrawerDescription>
                  </DrawerHeader>
                  <PlaylistContent
                    songs={songs}
                    currentSong={currentSong}
                    onSelect={handleSongSelect}
                  />
                </DrawerContent>
              </Drawer>
            )}
          </div>
          <audio
            ref={audioRef}
            title={currentSong?.name}
            onTimeUpdate={() => audioRef.current && setCurrentTime(audioRef.current.currentTime)}
            onLoadedMetadata={() => audioRef.current && setDuration(audioRef.current.duration)}
            onEnded={handleSongEnd}
          />
        </>
      )}
    </div>
  )
}

export default App
