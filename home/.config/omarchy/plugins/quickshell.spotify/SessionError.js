function message(stderr) {
  if (/does not support ["']?free|premium.*required|sign up for a premium/i.test(String(stderr)))
    return "Spotify reports this account as Free. Native Spotify needs Premium. Use the music panel's Open Spotify button for desktop playback."
  return "Spotify session stopped. Click Log in to reconnect."
}
