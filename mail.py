import contextlib
from imaplib2 import IMAP4_SSL
from email.parser import Parser
import re
import string
from pprint import pprint

class Mailbox():
  def __init__(self,connection,name,parent=None):
    self.c = connection
    self.parent   = parent
    self.name     = name
    self.children = {}

  def get_full_path(self):
    parent = self.parent
    full_path = [self.name]
    while parent != None and parent.name != "root":
      full_path.append(parent.name)
      parent = parent.parent

    full_path.reverse()

    return ".".join(full_path)

  def message_count(self):
    status, msg_count = self.c.examine(self.get_full_path())

    if status == "OK":
      return msg_count[0]
    else:
      return 0

  def create_child(self,parts):
    if self.has_child(parts[0]):
      # child already exists
      mb = self.children[parts[0]]
    else:
      mb = Mailbox(self.c,parts[0],parent=self)
      self.children[parts[0]] = mb

    if len(parts) > 1:
      mb.create_child(parts[1:])


  def has_child(self,name):
    return name in self.children.keys()

  def todict(self):
    result = {
      "name": self.name,
      "children": [c.todict() for c in self.children.values()],
      "full_path": self.get_full_path(),
      "msg_count": self.message_count()
      }

    return result

class VIMAP():
  @contextlib.contextmanager
  def connect(self,hostname,username,password):
    self.c = IMAP4_SSL(hostname)
    self.c.login(username,password)
    yield self.c
    self.close()

  def close(self):
    print("Logging out")
    self.c.logout()

  def headers(self,folder,uid):
    self.c.select(folder)
    status, data = self.c.uid("fetch",uid,"(BODY.PEEK[HEADER])")
    return Parser().parsestr(data[0][1])

  def parse_email_address(self,raw_email):
    raw_email = raw_email.strip()

    name  = ""
    email = ""

    if raw_email[-1] == ">":
      email = raw_email[raw_email.rfind("<")+1:-1]
      name  = raw_email[:raw_email.rfind("<")].strip()
    else:
      email = raw_email

    chars = string.lowercase + string.uppercase + " ."
    name = re.sub("[^" + chars + "]","",name)

    if len(name) == 0:
      name = email

    return {
      "email":email,
      "name": name
      }

  def dirlist(self):
    result = {}

    typ, data = self.c.list()

    list_response_pattern = re.compile(r'\((?P<flags>.*?)\) "(?P<delimiter>.*)" (?P<name>.*)')

    mailboxes = []

    for raw_dir in data:
      flags, delimiter, mailbox_name = list_response_pattern.match(raw_dir).groups()
      mailbox_name = mailbox_name.strip('"')
      mailboxes.append(mailbox_name)

    mailboxes = sorted(mailboxes)
    return self.dirlist_treegen(mailboxes)

  def dirlist_treegen(self,mailboxes):
    root = Mailbox(self.c,"root")

    for mb in mailboxes:
      parts = mb.split(".")

      root.create_child(parts)

    return root.todict()["children"]

if __name__ == "__main__":
  v = VIMAP()
  with v.connect("hostname","username","password") as c:
    v.dirlist()

    # c.select("INBOX",readonly=True)
    # status, [msg_uids] = c.uid("search",None,"ALL")
    # msg_uids = ",".join(msg_uids.split(" "))
    # status, data = c.uid("fetch",msg_uids,"(BODY.PEEK[HEADER])")

    # parse every other response from the fetch command why?
    # a ) is returned after each fetch.
    # for msg in data[::2]:
    #   h, raw_header = msg
    #   header = Parser().parsestr(raw_header)


    # for n in data[0].split():
    #   headers = v.headers("INBOX",n)
    #   print(headers["From"])
