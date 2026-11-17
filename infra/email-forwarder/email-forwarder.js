const { S3Client, GetObjectCommand } = require('@aws-sdk/client-s3');
const { SESClient, SendEmailCommand } = require('@aws-sdk/client-ses');

const s3 = new S3Client({ region: 'us-east-1' });
const ses = new SESClient({ region: 'us-east-1' });

// Email forwarding configuration, set as a Lambda environment variable so
// personal addresses stay out of the repo. Format (JSON):
//   FORWARD_MAPPING={"jeff@meatfestcatering.com":"someone@example.com", ...}
const forwardMapping = Object.fromEntries(
  Object.entries(JSON.parse(process.env.FORWARD_MAPPING || '{}'))
    .map(([from, to]) => [from.toLowerCase(), to])
);

exports.handler = async (event) => {
  console.log('Received SES event:', JSON.stringify(event, null, 2));

  const record = event.Records[0];
  const sesNotification = record.ses;
  const messageId = sesNotification.mail.messageId;
  const recipients = sesNotification.receipt.recipients;

  console.log('Processing message:', messageId);
  console.log('Recipients:', JSON.stringify(recipients));

  try {
    // Get the email from S3
    const getCommand = new GetObjectCommand({
      Bucket: 'meatfest-email-storage',
      Key: messageId
    });

    const data = await s3.send(getCommand);
    const rawEmail = await streamToString(data.Body);

    console.log('Email retrieved from S3, size:', rawEmail.length);

    // Parse headers from the raw email
    const headerEndIndex = rawEmail.indexOf('\r\n\r\n');
    const headers = rawEmail.substring(0, headerEndIndex);
    const body = rawEmail.substring(headerEndIndex + 4);

    // Extract original From and Subject
    const fromMatch = headers.match(/^From:\s*(.+)$/mi);
    const subjectMatch = headers.match(/^Subject:\s*(.+)$/mi);
    const originalFrom = fromMatch ? fromMatch[1].trim() : 'Unknown Sender';
    const originalSubject = subjectMatch ? subjectMatch[1].trim() : 'No Subject';

    console.log('Original From:', originalFrom);
    console.log('Original Subject:', originalSubject);

    // Forward to each recipient
    for (const recipient of recipients) {
      const forwardTo = forwardMapping[recipient.toLowerCase()];

      if (forwardTo) {
        console.log(`Forwarding email for ${recipient} to ${forwardTo}`);

        // Create a simple forwarded email
        const forwardedBody = `---------- Forwarded message ----------
From: ${originalFrom}
To: ${recipient}
Subject: ${originalSubject}

${extractTextBody(body)}`;

        const sendCommand = new SendEmailCommand({
          Source: 'meatfestcatering@gmail.com',
          Destination: {
            ToAddresses: [forwardTo]
          },
          Message: {
            Subject: {
              Data: `Fwd: ${originalSubject}`,
              Charset: 'UTF-8'
            },
            Body: {
              Text: {
                Data: forwardedBody,
                Charset: 'UTF-8'
              }
            }
          }
        });

        try {
          const result = await ses.send(sendCommand);
          console.log(`Successfully forwarded to ${forwardTo}, MessageId: ${result.MessageId}`);
        } catch (sendError) {
          console.error(`Failed to forward to ${forwardTo}:`, sendError);
          throw sendError;
        }
      } else {
        console.log(`No forwarding address configured for ${recipient}`);
      }
    }

    return { statusCode: 200, body: 'Email forwarded successfully' };
  } catch (error) {
    console.error('Error processing email:', error);
    throw error;
  }
};

// Helper function to convert stream to string
async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) {
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf-8');
}

// Extract text body from email (handles multipart)
function extractTextBody(body) {
  // If it's a simple text body, return it
  if (!body.includes('Content-Type:')) {
    return body;
  }

  // Try to find plain text part in multipart message
  const textMatch = body.match(/Content-Type:\s*text\/plain[^]*?(?:\r\n\r\n|\n\n)([^]*?)(?=--)/i);
  if (textMatch) {
    return textMatch[1].trim();
  }

  // Fallback: return the body as-is
  return body;
}
