const { SESv2Client, SendEmailCommand } = require('@aws-sdk/client-sesv2');
const { DynamoDBClient, PutItemCommand } = require('@aws-sdk/client-dynamodb');
const { v4: uuidv4 } = require('uuid');

const ses = new SESv2Client({});
const ddb = new DynamoDBClient({});

const TABLE_NAME = process.env.TABLE_NAME;
const TO_EMAIL = process.env.TO_EMAIL;
const FROM_EMAIL = process.env.FROM_EMAIL;

function corsHeaders(){
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Allow-Methods': 'OPTIONS,POST'
  };
}

function response(statusCode, body){
  return { statusCode, headers: corsHeaders(), body: JSON.stringify(body) };
}

function sanitize(s){
  if(typeof s !== 'string') return '';
  return s.replace(/[\u0000-\u001F\u007F]/g,'').trim();
}

exports.submit = async (event) => {
  if(event.requestContext && event.requestContext.http && event.requestContext.http.method === 'OPTIONS'){
    return { statusCode: 204, headers: corsHeaders(), body: '' };
  }

  let payload = {};
  try{
    payload = JSON.parse(event.body || '{}');
  }catch{
    return response(400, { message: 'Invalid JSON' });
  }

  const type = sanitize(payload.type || 'contact');
  const name = sanitize(payload.name);
  const email = sanitize(payload.email);
  const phone = sanitize(payload.phone);
  const eventDate = sanitize(payload.eventDate);
  const eventType = sanitize(payload.eventType);
  const headcount = sanitize(String(payload.headcount||''));
  const message = sanitize(payload.message);

  if(!name || !email){
    return response(400, { message: 'Name and email are required.' });
  }

  const id = uuidv4();
  const createdAt = new Date().toISOString();

  const item = {
    id: { S: id },
    createdAt: { S: createdAt },
    type: { S: type },
    name: { S: name },
    email: { S: email },
    phone: { S: phone },
    eventDate: { S: eventDate },
    eventType: { S: eventType },
    headcount: { S: headcount },
    message: { S: message }
  };

  try{
    await ddb.send(new PutItemCommand({ TableName: TABLE_NAME, Item: item }));
  }catch(err){
    console.error('DDB error', err);
    return response(500, { message: 'Could not save your request.' });
  }

  // Email to business owner
  const subject = type === 'request' ? `New Catering Request from ${name}` : `New Contact from ${name}`;
  const text = [
    `Type: ${type}`,
    `Created: ${createdAt}`,
    `Name: ${name}`,
    `Email: ${email}`,
    phone ? `Phone: ${phone}` : null,
    eventDate ? `Event Date: ${eventDate}` : null,
    eventType ? `Event Type: ${eventType}` : null,
    headcount ? `Headcount: ${headcount}` : null,
    '',
    'Message:',
    message || '(none)'
  ].filter(Boolean).join('\n');

  // Auto-responder email to customer
  const autoReplySubject = type === 'request'
    ? 'Thanks for your catering request!'
    : 'Thanks for contacting Meatfest Catering!';

  const autoReplyText = `Hi ${name},

Thanks for reaching out to Meatfest Catering! We've received your ${type === 'request' ? 'catering request' : 'message'} and will get back to you within 1 business day.

${type === 'request' && eventDate ? `We'll be in touch soon about your event on ${eventDate}.` : ''}

In the meantime, if you have urgent questions, feel free to call us at (614) 555-1234 (Mon-Fri 9am-6pm EST).

Thanks for considering Meatfest Catering for your event!

Best regards,
The Meatfest Catering Team
Columbus, Ohio

---
This is an automated confirmation. Please do not reply to this email.`;

  try{
    // Send notification to business owner
    await ses.send(new SendEmailCommand({
      FromEmailAddress: FROM_EMAIL,
      Destination: { ToAddresses: [TO_EMAIL] },
      Content: {
        Simple: {
          Subject: { Data: subject },
          Body: { Text: { Data: text } }
        }
      }
    }));

    // Send auto-reply to customer
    await ses.send(new SendEmailCommand({
      FromEmailAddress: FROM_EMAIL,
      Destination: { ToAddresses: [email] },
      Content: {
        Simple: {
          Subject: { Data: autoReplySubject },
          Body: { Text: { Data: autoReplyText } }
        }
      }
    }));
  }catch(err){
    console.error('SES error', err);
    // Still return success to not leak email failures to users
  }

  return response(200, { message: 'Submitted' });
};
