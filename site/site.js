const video = document.getElementById('demo-video');
const shell = document.getElementById('video-shell');

video.addEventListener('loadedmetadata', () => {
  shell.dataset.ready = 'true';
});

video.addEventListener('error', () => {
  shell.dataset.ready = 'false';
});
