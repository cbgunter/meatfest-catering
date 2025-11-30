(function(){
  const cfg = (window.MEATFEST_CONFIG||{});
  const apiBaseUrl = (cfg.apiBaseUrl||'').replace(/\/$/,'');

  function setStatus(el, type, msg){
    if(!el) return;
    el.hidden = !msg;
    el.className = 'notice ' + (type||'');
    el.textContent = msg||'';
  }

  function validateEmail(email){
    const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    return re.test(email);
  }

  async function submitForm(form, kind){
    const status = form.querySelector('[data-status]');
    const submitBtn = form.querySelector('button[type="submit"]');
    const fd = new FormData(form);

    const payload = {
      type: kind,
      name: fd.get('name')||'',
      email: fd.get('email')||'',
      phone: fd.get('phone')||'',
      eventDate: fd.get('eventDate')||'',
      eventLocation: fd.get('eventLocation')||'',
      eventType: fd.get('eventType')||'',
      headcount: fd.get('headcount')||'',
      message: fd.get('message')||'',
      honeypot: fd.get('website')||''
    };

    // Honeypot check - if filled, it's likely a bot
    if(payload.honeypot){
      console.log('Bot detected');
      return;
    }

    if(!apiBaseUrl){
      setStatus(status,'error','Form backend not configured yet. See README to connect forms.');
      return;
    }

    if(!payload.name || !payload.email){
      setStatus(status,'error','Please provide your name and email.');
      return;
    }

    if(!validateEmail(payload.email)){
      setStatus(status,'error','Please enter a valid email address.');
      return;
    }

    if(!payload.message){
      setStatus(status,'error','Please provide a message.');
      return;
    }

    try{
      setStatus(status,'', 'Sending your request...');
      submitBtn.disabled = true;
      submitBtn.style.opacity = '0.6';
      submitBtn.innerHTML = '⏳ Sending...';

      const res = await fetch(apiBaseUrl + '/submit',{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body: JSON.stringify(payload)
      });
      const data = await res.json().catch(()=>({}));
      if(!res.ok){
        throw new Error(data.message || ('Request failed with ' + res.status));
      }
      form.reset();
      setStatus(status,'success','✓ Thanks! We received your request and will reach out soon.');
      submitBtn.innerHTML = '✓ Sent!';
      setTimeout(() => {
        submitBtn.innerHTML = kind === 'request' ? 'Submit Request' : 'Send Message';
      }, 3000);
    }catch(err){
      setStatus(status,'error', '✗ ' + (err.message || 'Something went wrong. Please try again.'));
      submitBtn.innerHTML = kind === 'request' ? 'Submit Request' : 'Send Message';
    }finally{
      submitBtn.disabled = false;
      submitBtn.style.opacity = '1';
    }
  }

  function bindForm(id, kind){
    const form = document.getElementById(id);
    if(!form) return;
    const status = document.createElement('div');
    status.setAttribute('data-status','');
    status.className = 'notice';
    status.hidden = true;
    form.prepend(status);
    form.addEventListener('submit', (e)=>{
      e.preventDefault();
      submitForm(form, kind);
    });
  }

  document.addEventListener('DOMContentLoaded', function(){
    bindForm('request-form','request');
    bindForm('contact-form','contact');
  });
})();
