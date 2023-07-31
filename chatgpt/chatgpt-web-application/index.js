const ldap = require('ldapjs');
const Redis = require("redis");
const mysql = require('mysql');
const express = require('express');
const {Configuration, OpenAIApi} = require("openai");
const app = express();
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const multer  = require('multer');
const { v4: uuidv4 } = require('uuid');
require("dotenv").config();
const configuration = new Configuration({
    apiKey: process.env.OPENAI_API_KEY
});



var con = mysql.createConnection({
  host: process.env.MYSQL_HOST,
  user:process.env.MYSQL_USER,
  password:process.env.MYSQL_PASSWORD,
  database:process.env.MYSQL_DATABASE
});
const openai = new OpenAIApi(configuration);

const redisclient = Redis.createClient({
    username: process.env.REDIS_USER, 
    password: process.env.REDIS_PASSWORD, 
    socket: {
      host: process.env.REDIS_HOST,
      port: 6379
    }
  });

app.use(cors());
app.use(express.json());
app.use('/', express.static(__dirname + '/client')); // Serves resources from client folder

// Set up Multer to handle file uploads
const upload = multer({
    storage: multer.diskStorage({
        destination: function (req, file, cb) {
            cb(null, 'uploads/')
        },
        filename: function (req, file, cb) {
            const extension = path.extname(file.originalname);
            const filename = uuidv4() + extension;
            cb(null, filename);
        }
    }),
    limits: { fileSize: 1024 * 1024 * 10 }, // 10 MB
    fileFilter: function (req, file, cb) {
        const allowedExtensions = ['.mp3', '.mp4', '.mpeg', '.mpga', '.m4a', '.wav', '.webm'];
        const extension = path.extname(file.originalname);
        if (allowedExtensions.includes(extension)) {
            cb(null, true);
        } else {
            cb(new Error('Invalid file type.'));
        }
    }
});

app.post('/transcribe', upload.single('audio'), async (req, res) => {
    try {
        const resp = await openai.createTranscription(
            fs.createReadStream(req.file.path),
            "whisper-1",
            'text'
        );
        return res.send(resp.data.text);
    } catch (error) {
        const errorMsg = error.response ? error.response.data.error : `${error}`;
        console.log(errorMsg)
        return res.status(500).send(errorMsg);
    } finally {
        fs.unlinkSync(req.file.path);
    }
});

app.post("/login", async (req, res) => {
    const {email, password} = req.body;


          const sessionId=Math.floor(Math.random() * 999999999) + 1;
          const sql="select * from User where email='"+email+"' and password='"+password+"'";
          con.query(sql, (err, rows) => {
              if (err){
                  return res.status(400).send({error: 'error'}); }
              else{
                  if(rows.length==0){
                  return res.status(200).send({message: false});
              }
                  else{
                    return res.status(200).send({message: true,id:email,sessionId:sessionId});
                  }
              }
              })
      });



      
    






app.post("/register", async (req, res) => {
      const {name,email, password} = req.body;
      const sql="insert into User (name,email,password) values ('"+name+"','"+email+"','"+password+"')";
      con.query(sql, (err, rows) => {
          if (err){
              return res.status(200).send({message: false}); }
          else{
              return res.status(200).send({message: true});
          }
          })
  });


app.post('/get-prompt-result', async (req, res) => {
    // Get the prompt from the request body
    const {prompt, model = 'gpt',id} = req.body;

    // Check if prompt is present in the request
    if (!prompt) {
        // Send a 400 status code and a message indicating that the prompt is missing
        return res.status(400).send({error: 'Prompt is missing in the request'});
    }

    try {
        // Use the OpenAI SDK to create a completion
        // with the given prompt, model and maximum tokens
        if (model === 'image') {
            const result = await openai.createImage({
                prompt,
                response_format: 'url',
                size: '512x512'
            });
            return res.send(result.data.data[0].url);
        }
        if (model === 'chatgpt') {

            await setter(id,"user",prompt)
            const histroy=await getter(id);
            const result = await openai.createChatCompletion({
                model:"gpt-3.5-turbo-0301",
                messages:histroy
            })
            //console.log(result.data.choices[0]?.message?.content)
            await setter(id,"assistant",result.data.choices[0]?.message?.content)
            return res.send(result.data.choices[0]?.message?.content);
        }
        const completion = await openai.createCompletion({
            model: 'text-davinci-003', // model name
            prompt: `Please reply below question in markdown format.\n ${prompt}`, // input prompt
            max_tokens: 4000
        });
        // Send the generated text as the response
        return res.send(completion.data.choices[0].text);
    } catch (error) {
        const errorMsg = error.response ? error.response.data.error : `${error}`;
        console.error(errorMsg);
        // Send a 500 status code and the error message as the response
        return res.status(500).send(errorMsg);
    }
});

const port = process.env.PORT || 3001;
app.listen(port, () => console.log(`Listening on port ${port}`));


async function setter(id,roLe,msg) {
    console.log("setter")
    console.log(id)
    try {
        await redisclient.connect();
      } catch (err) {
        console.log(err)
        await redisclient.disconnect();
        await redisclient.connect();

      }
    const value = await redisclient.get(id);
    console.log(value)

    if (value == null){
        await redisclient.set(id,JSON.stringify({role : roLe, content : msg}));
    }
    else{



    await redisclient.append(id,","+JSON.stringify({role : roLe, content : msg}))

    }
    await redisclient.disconnect();
  }


  async function getter(id) {
    console.log("getter")
    try {
      await redisclient.connect();
    } catch (err) {
      console.log(err)
      await redisclient.disconnect();
      await redisclient.connect();

    }


    const value = "["+ await redisclient.get(id)+"]"
    let valueee = value.replace('"content"', 'content');
    valueee = valueee.replace('"role"', 'role');
    console.log(valueee)
    const valuee=eval('(' + valueee+ ')');

    console.log("end of getter")
    await redisclient.disconnect();
    return valuee
  }