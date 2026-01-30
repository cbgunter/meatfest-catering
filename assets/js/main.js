(function(){
  // Simple mobile menu toggle if needed later
  const btn = document.querySelector('[data-menu-toggle]');
  const nav = document.querySelector('[data-nav]');
  if(btn && nav){
    btn.addEventListener('click',()=>{
      nav.classList.toggle('open');
    });
  }

  // Image Carousel
  const slides = document.querySelectorAll('.carousel-slide');
  const dots = document.querySelectorAll('.carousel-dot');
  if(slides.length > 0 && dots.length > 0){
    let currentSlide = 0;
    let autoRotate;

    function showSlide(index){
      slides.forEach(s => s.classList.remove('active'));
      dots.forEach(d => d.classList.remove('active'));
      slides[index].classList.add('active');
      dots[index].classList.add('active');
      currentSlide = index;
    }

    function nextSlide(){
      const next = (currentSlide + 1) % slides.length;
      showSlide(next);
    }

    function startAutoRotate(){
      autoRotate = setInterval(nextSlide, 4000);
    }

    function stopAutoRotate(){
      clearInterval(autoRotate);
    }

    // Dot click handlers
    dots.forEach((dot, i) => {
      dot.addEventListener('click', () => {
        stopAutoRotate();
        showSlide(i);
        startAutoRotate();
      });
    });

    // Pause on hover
    const container = document.querySelector('.carousel-container');
    if(container){
      container.addEventListener('mouseenter', stopAutoRotate);
      container.addEventListener('mouseleave', startAutoRotate);
    }

    // Start auto-rotation
    startAutoRotate();
  }
})();
