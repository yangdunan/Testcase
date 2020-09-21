import re

reg_list = []
def parse_reg_name():
    print("========================parse_reg_name start================================")
    with open('picorv32.v', "r") as reader:
        for i,line in enumerate(reader.readlines(),0):
            line = line.strip()
            # print(line)
            if (re.match(" ?reg ",line)):
                if (line.find("]") == -1):
                    if len(line.split(","))==1:
                        if(line.split("reg")[1].strip().replace(";","").find("=") ==- 1):
                            reg_list.append(line.split("reg")[1].strip().replace(";",""))
                        else:
                            reg_list.append(line.split("reg")[1].strip().replace(";","").split("=")[0].strip())
                    else:
                        reg_name = line.split("reg")[1].strip()
                        reg_name = reg_name.split(",")
                        for reg in reg_name:
                            reg_list.append(reg.strip().replace(";",""))
                else:
                    if len(line.split(","))==1:
                        if (line.split("]")[1].strip().find("[")==-1):
                            if (line.split("]")[1].strip().find("=") == -1):
                                reg_list.append(line.split("]")[1].strip().replace(";",""))
                            else:
                                reg_list.append(line.split("]")[1].strip().replace(";","").split("=")[0].strip())
                        else:
                            reg_list.append(line.split("]")[1].strip().split("[")[0].strip().replace(";",""))
                    else:
                        reg_name = line.split("]")[1].strip()
                        reg_name = reg_name.split(",")
                        for reg in reg_name:
                            reg_list.append(reg.strip().replace(";",""))  
            else:
                # print(line)
                continue
    print(reg_list)
    print(len(reg_list))
    print("========================parse_reg_name done===================================")




def rewrite_format():
    print("========================rewrite_format start===================================")

    with open('picorv32.v', "r") as reader:
        with open ('picorv32_rewrite_format.v', "w") as writer:
            # for i,line in enumerate(reader.readlines(),0):
            
            for line in reader:

                line = line.strip()
                if (re.match(" ?if ?",line)):
                    if line.endswith("begin"):
                            writer.write(("{}\n").format(line))
                            
                    else:
                        if line.endswith(";"):
                            line = re.split(r"\) ",line)
                            writer.write(("{}) begin\n").format(line[0]))
                            writer.write(("{}\n").format(line[1]))
                            writer.write("end\n")
                            
                        elif line.endswith(")"):
                            writer.write(("{} begin\n").format(line))
                            next_line = reader.next().strip()
                            writer.write(("{} \n").format(next_line))
                            writer.write("end\n")
                        else:
                            if line.endswith(";"):
                                
                                writer.write(("{}\n").format(line))
                            elif   line.find("begin") == -1:  
                                while not(line.endswith(";")):
                                    writer.write(("{}").format(line.replace("assign","")))
                                    line = reader.next().strip()
                                writer.write(("{}\n").format(line.replace("assign","")))
                                writer.write("end\n")
                            else:
                                writer.write(("{}\n").format(line))  
                elif line.find(": ") is not -1 and line.find("?") == -1 and \
                    line.find("wire") == -1 and line.find("reg") is -1 and \
                    line.find("$") is -1 and line.find("para") is -1 and \
                    line.find("put") is -1 and line.find("+: ") is -1:
                    if line.endswith(":"):
                        writer.write(("{} begin\n").format(line))
                        next_line = reader.next().strip()
                        writer.write(("{} \n").format(next_line))
                        writer.write("end\n")
                    else:
                        
                        if  (line.find("begin")) == -1 and line.endswith(";"):
                            writer.write(("{}: begin\n").format(re.split(r"(:)",line)[0]))
                            string = ""
                            for char in re.split(r"(:)",line)[2:]:
                                string += char
                            writer.write(("{}\n").format(string))
                            writer.write("end\n")

                        else:
                            if line.endswith(";"):
                                writer.write(("{}\n").format(line))
                            elif   line.find("begin") == -1:  
                                while not(line.endswith(";")):
                                    writer.write(("{}").format(line.replace("assign","")))
                                    line = reader.next().strip()
                                writer.write(("{}\n").format(line.replace("assign","")))
                                writer.write("end\n")
                            else:
                                
                                writer.write(("{}\n").format(line))
                else:

                    if line.find("=") is not -1 and not line.endswith(";") and line.find("para") is  -1:
                        if line.endswith(";"):
                                
                                writer.write(("{}\n").format(line))
                        elif   line.find("begin") == -1  :  
                            while not(line.endswith(";")):
                                writer.write(("{}").format(line))
                                line = reader.next().strip()
                            writer.write(("{}\n").format(line))
                        else:
                            writer.write(("{}\n").format(line))  
                    elif line.endswith(":"):
                        writer.write(("{} begin\n").format(line))
                        next_line = reader.next().strip()
                        writer.write(("{} \n").format(next_line))
                        writer.write("end\n")
                    elif line.find("always") is not -1 and line.find("begin") is -1:
                        if line.endswith(";"):
                            writer.write(("{}) begin\n").format(line.split(")")[0]))
                            writer.write(("{} \n").format(line.split(")")[1]))
                            writer.write("end \n")
                        else:
                            writer.write(("{} begin\n").format(line))
                            next_line = reader.next().strip()
                            writer.write(("{} \n").format(next_line))
                            writer.write("end\n")
                    else:
                        if line.find(":") is not -1 and line.find("[") is -1 and line.find("=") is not -1 and line.find("?") is -1 :
                            writer.write(("{}: begin\n").format(line.split(":")[0]))
                            writer.write(("{} \n").format(line.split(":")[1]))
                            writer.write("end \n")
                        else:
                            writer.write(('{}\n').format(line))
    
    print("========================rewrite_format done===================================")
def add_display():
    print("========================add_display start===================================")
    with open('picorv32_rewrite_format.v', "r") as reader:
        with open ('picorv32_add_display.v', "w") as writer:
            for line in reader:
                line =line.strip()
                if  (line.find("=")) is not -1 and line.find("para") is -1 and \
                    line.find("wire") is -1 and line.find("assign") is -1\
                        and line.find("for") is -1 :
                    if line.find("if") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    elif line.find("case") is not -1 and line.find("(") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    else:
                        writer.write(("{} \n").format(line))
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                else:
                    if line.find("if") is not -1 and line.find("(") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    elif line.find("case") is not -1 and line.find("(") is not -1:
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write(("{} \n").format(line))
                    elif line.find("assign") is not -1 :
                        writer.write(("{} \n").format(line))
                        writer.write("always@* begin \n")
                        writer.write(("$fwrite(f,\"%0d cycle :{}\\n\"  , count_cycle); \n").format(line.replace("\"","\\\"").replace("\'","\\\'")))
                        writer.write("end \n")

                    else:
                        writer.write(("{} \n").format(line))
                




    print("========================add_display done===================================")




if __name__ =="__main__":
    # parse_reg_name()
    rewrite_format()
    add_display()
