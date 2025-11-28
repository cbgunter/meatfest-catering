(function(){
  // Simple mobile menu toggle if needed later
  const btn = document.querySelector('[data-menu-toggle]');
  const nav = document.querySelector('[data-nav]');
  if(btn && nav){
    btn.addEventListener('click',()=>{
      nav.classList.toggle('open');
    });
  }
})();
